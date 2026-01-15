#!/usr/bin/env ruby
# frozen_string_literal: true

# Complete working example for agent_runtime
# Copy-paste this into bin/console to test

require "agent_runtime"
require "ollama_client"

# 1. Set up tools
tools = AgentRuntime::ToolRegistry.new({
  "fetch" => ->(**args) {
    { data: "Fetched data for: #{args.inspect}", timestamp: Time.now.utc.iso8601 }
  },
  "execute" => ->(**args) {
    { result: "Executed action: #{args.inspect}", success: true }
  },
  "analyze" => ->(**args) {
    { analysis: "Analysis result for: #{args.inspect}", confidence: 0.85 }
  }
})

# 2. Configure Ollama client
client = Ollama::Client.new

# 3. Create planner
planner = AgentRuntime::Planner.new(
  client: client,
  schema: {
    "type" => "object",
    "required" => ["action", "params", "confidence"],
    "properties" => {
      "action" => {
        "type" => "string",
        "enum" => ["fetch", "execute", "analyze", "finish"],
        "description" => "The action to take"
      },
      "params" => {
        "type" => "object",
        "additionalProperties" => true,
        "description" => "Parameters for the action (any key-value pairs allowed)"
      },
      "confidence" => {
        "type" => "number",
        "minimum" => 0,
        "maximum" => 1,
        "description" => "Confidence level"
      }
    }
  },
  prompt_builder: ->(input:, state:) {
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

# 4. Create policy
policy = AgentRuntime::Policy.new

# 5. Create executor
executor = AgentRuntime::Executor.new(tool_registry: tools)

# 6. Create state
state = AgentRuntime::State.new

# 7. Create agent
agent = AgentRuntime::Agent.new(
  planner: planner,
  policy: policy,
  executor: executor,
  state: state,
  audit_log: AgentRuntime::AuditLog.new
)

# 8. Test single step
puts "=" * 60
puts "Testing Agent.step()"
puts "=" * 60

begin
  result = agent.step(input: "Fetch market data for AAPL")
  puts "\n✅ Success!"
  puts "Result: #{result.inspect}"
rescue Ollama::RetryExhaustedError => e
  puts "\n❌ Ollama server error: #{e.message}"
  puts "Check if Ollama server is running and model is available"
rescue Ollama::NotFoundError => e
  puts "\n❌ Model not found: #{e.message}"
rescue AgentRuntime::PolicyViolation => e
  puts "\n❌ Policy violation: #{e.message}"
rescue => e
  puts "\n❌ Error: #{e.class}: #{e.message}"
  puts e.backtrace.first(5)
end

puts "\n" + "=" * 60
puts "Agent state after step:"
puts state.snapshot.inspect
puts "=" * 60
