# frozen_string_literal: true

# Background job for async agent processing
# Use this for long-running analyses or when you want to avoid blocking the request
class BillingAnalysisJob < ApplicationJob
  queue_as :default

  # Perform async billing analysis
  # @param user_id [Integer] User requesting the analysis
  # @param question [String] User's billing question
  # @param session_id [String] Optional session identifier for state persistence
  def perform(user_id:, question:, session_id: nil)
    user = User.find(user_id)

    # Load or create agent state for this session
    state = load_agent_state(session_id || user.id)

    # Create agent with persisted state
    agent = build_agent_with_state(state)

    result = agent.step(input: question)

    # Persist updated state
    save_agent_state(session_id || user.id, agent.instance_variable_get(:@state))

    # Notify user (via ActionCable, email, etc.)
    notify_user(user, result)

    result
  rescue StandardError => e
    Rails.logger.error("BillingAnalysisJob failed: #{e.message}")
    raise
  end

  private

  def build_agent_with_state(state)
    config = Ollama::Config.new
    config.base_url = ENV.fetch("OLLAMA_URL", "http://localhost:11434")
    client = Ollama::Client.new(config: config)

    planner = AgentRuntime::Planner.new(
      client: client,
      schema: BillingAgent.decision_schema,
      prompt_builder: BillingAgent.method(:build_prompt)
    )

    policy = BillingPolicy.new
    executor = BillingExecutor.new
    audit_log = AgentRuntime::AuditLog.new

    AgentRuntime::Agent.new(
      planner: planner,
      policy: policy,
      executor: executor,
      state: state,
      audit_log: audit_log
    )
  end

  def load_agent_state(session_id)
    # In real app, load from Redis, database, etc.
    stored = Rails.cache.read("agent_state:#{session_id}")
    stored ? AgentRuntime::State.new(stored) : AgentRuntime::State.new
  end

  def save_agent_state(session_id, state)
    # In real app, save to Redis, database, etc.
    Rails.cache.write(
      "agent_state:#{session_id}",
      state.snapshot,
      expires_in: 1.hour
    )
  end

  def notify_user(user, result)
    # In real app, send via ActionCable, email, etc.
    Rails.logger.info("Analysis complete for user #{user.id}: #{result.inspect}")
  end
end
