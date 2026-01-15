# frozen_string_literal: true

require "agent_runtime"
require "ollama_client"

# Domain-specific agent for billing analysis
# This is a Rails model, but the agent itself is domain-agnostic
class BillingAgent
  def self.instance
    @instance ||= build
  end

  def self.build
    config = Ollama::Config.new
    config.base_url = ENV.fetch("OLLAMA_URL", "http://localhost:11434")
    client = Ollama::Client.new(config: config)

    planner = AgentRuntime::Planner.new(
      client: client,
      schema: decision_schema,
      prompt_builder: method(:build_prompt)
    )

    policy = BillingPolicy.new
    executor = BillingExecutor.new
    state = AgentRuntime::State.new
    audit_log = AgentRuntime::AuditLog.new

    AgentRuntime::Agent.new(
      planner: planner,
      policy: policy,
      executor: executor,
      state: state,
      audit_log: audit_log
    )
  end

  def self.decision_schema
    {
      "action" => "string",
      "params" => {
        "invoice_id" => "string",
        "customer_id" => "string",
        "explanation" => "string"
      },
      "confidence" => "number"
    }
  end

  def self.build_prompt(input:, state:)
    <<~PROMPT
      You are a billing analysis assistant. Analyze the user's question about billing.

      User question: #{input}

      Current context: #{state.to_json}

      Respond with:
      - action: "analyze" or "fetch_invoice" or "finish"
      - params: relevant invoice/customer IDs and explanation
      - confidence: your confidence level (0.0 to 1.0)
    PROMPT
  end

  private_class_method :build
end

# Domain-specific policy for billing
class BillingPolicy < AgentRuntime::Policy
  def validate!(decision, state:)
    super

    allowed_actions = %w[analyze fetch_invoice finish]
    unless allowed_actions.include?(decision.action)
      raise AgentRuntime::PolicyViolation, "Action not allowed: #{decision.action}"
    end

    return unless decision.action == "fetch_invoice" && !decision.params&.dig("invoice_id")

    raise AgentRuntime::PolicyViolation, "fetch_invoice requires invoice_id"
  end
end

# Domain-specific executor with billing tools
class BillingExecutor < AgentRuntime::Executor
  def initialize
    tools = AgentRuntime::ToolRegistry.new(
      "analyze" => method(:analyze_billing),
      "fetch_invoice" => method(:fetch_invoice)
    )
    super(tool_registry: tools)
  end

  private

  def analyze_billing(invoice_id: nil, customer_id: nil, explanation: nil)
    {
      analysis: explanation || "No explanation provided",
      invoice_id: invoice_id,
      customer_id: customer_id,
      timestamp: Time.now.utc.iso8601
    }
  end

  def fetch_invoice(invoice_id:)
    # In real app, this would query your database
    {
      invoice: {
        id: invoice_id,
        amount: 100.00,
        status: "paid",
        created_at: "2024-01-15"
      }
    }
  end
end
