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
      "type" => "object",
      "required" => %w[action params],
      "properties" => {
        "action" => {
          "type" => "string",
          "enum" => %w[analyze fetch_invoice finish],
          "description" => "The action to execute"
        },
        "params" => {
          "type" => "object",
          "properties" => {
            "invoice_id" => {
              "type" => "string",
              "description" => "Invoice identifier"
            },
            "customer_id" => {
              "type" => "string",
              "description" => "Customer identifier"
            },
            "explanation" => {
              "type" => "string",
              "description" => "Analysis explanation"
            }
          },
          "additionalProperties" => true
        },
        "confidence" => {
          "type" => "number",
          "minimum" => 0,
          "maximum" => 1,
          "description" => "Confidence level (0.0 to 1.0)"
        }
      }
    }
  end

  def self.build_prompt(input:, state:)
    <<~PROMPT
      You are a billing analysis assistant. Analyze the user's question about billing.

      User Question: #{input}

      Current State: #{state.to_json}

      Available Actions:
      - analyze: Analyze billing data (requires: invoice_id, customer_id, explanation)
      - fetch_invoice: Fetch invoice details (requires: invoice_id)
      - finish: Complete the task

      Respond with a JSON object:
      {
        "action": "one of the available actions",
        "params": { "invoice_id": "123", "customer_id": "456", "explanation": "..." },
        "confidence": 0.9
      }
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
