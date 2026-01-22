#!/usr/bin/env ruby
# frozen_string_literal: true

# Fixed example with correct schema format
# Copy-paste this into bin/console

require "agent_runtime"
require "ollama_client"

# 1. Set up tools
tools = AgentRuntime::ToolRegistry.new({
                                         "fetch" => ->(**args) { { data: "fetched", args: args } },
                                         "execute" => ->(**args) { { result: "executed", args: args } }
                                       })

# 2. Configure Ollama client with explicit model
config = Ollama::Config.new
config.model = "llama3.1:8b" # Use one of your available models
client = Ollama::Client.new(config: config)

# 3. Create planner with CORRECT schema format (full JSON Schema)
schema = {
  "type" => "object",
  "required" => %w[action params confidence],
  "properties" => {
    "action" => {
      "type" => "string",
      "enum" => %w[fetch execute analyze finish],
      "description" => "The action to take"
    },
    "params" => {
      "type" => "object",
      "additionalProperties" => true, # CRITICAL: Allows LLM to add any properties
      "description" => "Parameters for the action (any key-value pairs allowed)"
    },
    "confidence" => {
      "type" => "number",
      "minimum" => 0,
      "maximum" => 1,
      "description" => "Confidence level"
    }
  }
}

planner = AgentRuntime::Planner.new(
  client: client,
  schema: schema,
  prompt_builder: lambda { |input:, state:|
    <<~PROMPT
      You are a helpful assistant. Analyze the user's request and decide on an action.

      User request: #{input}

      Current state: #{state.to_json}

      Available actions:
      - fetch: Fetch data or information
      - execute: Execute an action
      - analyze: Analyze information
      - finish: Complete the task

      Respond with a JSON object containing:
      - action: one of the available actions
      - params: parameters needed for the action
      - confidence: your confidence level (0.0 to 1.0)
    PROMPT
  }
)

# 4. Define convergence policy (prevents infinite loops)
class ConvergentPolicy < AgentRuntime::Policy
  def converged?(state)
    # Converge when a tool has been called
    state.progress.include?(:tool_called)
  end
end

policy = ConvergentPolicy.new

# 5. Initialize state
state = AgentRuntime::State.new

# 6. Create agent
agent = AgentRuntime::Agent.new(
  planner: planner,
  executor: AgentRuntime::Executor.new(tool_registry: tools),
  policy: policy,
  state: state,
  audit_log: AgentRuntime::AuditLog.new
)

# 7. Run single step
begin
  result = agent.step(input: "Fetch market data for AAPL")
  puts "✅ Success!"
  puts "Result: #{result.inspect}"
rescue Ollama::RetryExhaustedError => e
  puts "❌ Ollama server error: #{e.message}"
  puts "Make sure Ollama server is running: ollama serve"
rescue Ollama::NotFoundError => e
  puts "❌ Model not found: #{e.message}"
rescue AgentRuntime::PolicyViolation => e
  puts "❌ Policy violation: #{e.message}"
rescue StandardError => e
  puts "❌ Error: #{e.class}: #{e.message}"
  puts e.backtrace.first(5)
end

puts "\nProgress signals: #{state.progress.signals.inspect}"
