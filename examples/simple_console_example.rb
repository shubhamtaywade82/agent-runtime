#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple console example - Copy-paste into bin/console
# Demonstrates: single-step, multi-step, and convergence

require "agent_runtime"
require "ollama_client"

# 1. Simple tool
tools = AgentRuntime::ToolRegistry.new({
                                         "get_time" => -> { { time: Time.now.utc.iso8601 } },
                                         "calculate" => lambda { |a:, b:, operation: "add"|
                                           result = case operation.to_s.downcase
                                                    when "add", "+"
                                                      a + b
                                                    when "subtract", "-"
                                                      a - b
                                                    when "multiply", "*"
                                                      a * b
                                                    when "divide", "/"
                                                      b.zero? ? "Error: Division by zero" : a.to_f / b
                                                    else
                                                      a + b # default to addition
                                                    end
                                           { result: result, operation: operation, a: a, b: b }
                                         }
                                       })

# 2. Ollama client
config = Ollama::Config.new
config.model = ENV.fetch("OLLAMA_MODEL", "llama3.1:8b")
client = Ollama::Client.new(config: config)

# 3. Schema
schema = {
  "type" => "object",
  "required" => %w[action],
  "properties" => {
    "action" => {
      "type" => "string",
      "enum" => %w[get_time calculate finish],
      "description" => "Action to execute"
    },
    "params" => {
      "type" => "object",
      "additionalProperties" => true
    },
    "confidence" => {
      "type" => "number",
      "minimum" => 0,
      "maximum" => 1
    }
  }
}

# 4. Planner
planner = AgentRuntime::Planner.new(
  client: client,
  schema: schema,
  prompt_builder: lambda { |input:, state:|
    "User request: #{input}\n\nAvailable actions:\n- get_time: Get current time\n- calculate(a:, b:, operation:): Calculate (operation can be 'add', 'subtract', 'multiply', 'divide', or '+', '-', '*', '/')\n- finish: Complete task"
  }
)

# 5. Convergence policy (halts when tool is called)
class SimplePolicy < AgentRuntime::Policy
  def converged?(state)
    return false unless state.respond_to?(:progress)

    state.progress.include?(:tool_called)
  end
end

# 6. Create agent (make available in console scope)
state = AgentRuntime::State.new
policy = SimplePolicy.new
agent = AgentRuntime::Agent.new(
  planner: planner,
  policy: policy,
  executor: AgentRuntime::Executor.new(tool_registry: tools),
  state: state,
  max_iterations: 5
)

# Make variables available in console (instance variables on main)
if defined?(IRB)
  @state = state
  @agent = agent
  @policy = policy
  @tools = tools
  @planner = planner
end

puts "\n✅ Agent ready!"
puts "\nVariables available: @agent, @state, @policy, @tools, @planner"
puts "  (Use @agent and @state in console - instance variables are available after load)"
puts "\nTry these commands:"
puts "  # Single-step (one execution)"
puts "  result = @agent.step(input: 'What time is it?')"
puts "  @state.progress.signals  # Check progress signals"
puts ""
puts "  # Multi-step (loops until convergence)"
puts "  result = @agent.run(initial_input: 'Get the current time')"
puts "  @state.progress.signals  # Should include :tool_called"
puts "  @policy.converged?(@state)  # Should be true"
puts ""
puts "  # Test calculation"
puts "  result = @agent.step(input: 'Calculate 5 + 3')"
puts "  result[:result]  # Should be 8"
puts "  # Or: result = @agent.step(input: 'Calculate 10 * 3')"
puts "  # result[:result]  # Should be 30"
puts ""
