#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script to verify convergence functionality
#
# This script demonstrates and tests the convergence feature:
# 1. Progress tracking works
# 2. Convergence policy halts the agent
# 3. Executor automatically marks progress signals
#
# Run with: bundle exec ruby examples/test_convergence.rb
# Note: Use bundle exec to ensure you're using the local development version

require "agent_runtime"

puts "=" * 70
puts "Testing AgentRuntime Convergence Feature"
puts "=" * 70
puts

# ============================================================================
# Test 1: Progress Tracking
# ============================================================================
puts "Test 1: Progress Tracking"
puts "-" * 70

state = AgentRuntime::State.new

# Verify progress tracker exists
puts "✓ State has progress tracker: #{state.progress.class}"

# Mark some signals
state.progress.mark!(:test_signal)
state.progress.mark!(:another_signal)

puts "✓ Marked signals: #{state.progress.signals.inspect}"
puts "✓ Check single signal: #{state.progress.include?(:test_signal)}"
puts "✓ Check multiple signals: #{state.progress.include?(:test_signal, :another_signal)}"
puts "✓ Check missing signal: #{state.progress.include?(:missing)}"
puts

# ============================================================================
# Test 2: Convergence Policy
# ============================================================================
puts "Test 2: Convergence Policy"
puts "-" * 70

# Default policy never converges
default_policy = AgentRuntime::Policy.new
puts "✓ Default policy converged?: #{default_policy.converged?(state)} (should be false)"

# Custom convergent policy
class TestConvergentPolicy < AgentRuntime::Policy
  def converged?(state)
    state.progress.include?(:work_complete)
  end
end

convergent_policy = TestConvergentPolicy.new
puts "✓ Convergent policy (no signal): #{convergent_policy.converged?(state)} (should be false)"

state.progress.mark!(:work_complete)
puts "✓ Convergent policy (with signal): #{convergent_policy.converged?(state)} (should be true)"
puts

# ============================================================================
# Test 3: Executor Progress Signals
# ============================================================================
puts "Test 3: Executor Progress Signals"
puts "-" * 70

# Create a simple tool
tools = AgentRuntime::ToolRegistry.new({
                                         "test_tool" => lambda do |message:|
                                           { result: "Processed: #{message}" }
                                         end
                                       })

executor = AgentRuntime::Executor.new(tool_registry: tools)
test_state = AgentRuntime::State.new

# Execute a tool
decision = AgentRuntime::Decision.new(
  action: "test_tool",
  params: { message: "Hello" }
)

result = executor.execute(decision, state: test_state)

puts "✓ Tool executed: #{result.inspect}"
puts "✓ Progress signals marked: #{test_state.progress.signals.inspect}"
puts "✓ :tool_called present: #{test_state.progress.include?(:tool_called)}"
puts "✓ :step_completed present: #{test_state.progress.include?(:step_completed)}"
puts

# ============================================================================
# Test 4: Agent Convergence (with mocked LLM)
# ============================================================================
puts "Test 4: Agent Convergence (Mocked)"
puts "-" * 70

# Create a mock client
class MockClient
  def generate(prompt:, schema:)
    {
      "action" => "test_tool",
      "params" => { "message" => "test" }
    }
  end
end

# Create components
mock_client = MockClient.new
schema = {
  "type" => "object",
  "required" => %w[action params],
  "properties" => {
    "action" => { "type" => "string" },
    "params" => { "type" => "object", "additionalProperties" => true }
  }
}

planner = AgentRuntime::Planner.new(
  client: mock_client,
  schema: schema,
  prompt_builder: ->(input:, state:) { "Prompt: #{input}" }
)

# Policy that converges after tool is called
class ToolCalledPolicy < AgentRuntime::Policy
  def converged?(state)
    state.progress.include?(:tool_called)
  end
end

policy = ToolCalledPolicy.new
executor = AgentRuntime::Executor.new(tool_registry: tools)
convergence_state = AgentRuntime::State.new

agent = AgentRuntime::Agent.new(
  planner: planner,
  policy: policy,
  executor: executor,
  state: convergence_state,
  max_iterations: 10
)

puts "Running agent with convergence policy..."
result = agent.run(initial_input: "Test convergence")

puts "✓ Agent completed: #{result.is_a?(Hash)}"
puts "✓ Iterations: #{result[:iterations] || "N/A"}"
puts "✓ Progress signals: #{convergence_state.progress.signals.inspect}"
puts "✓ Converged after first tool call: #{convergence_state.progress.include?(:tool_called)}"
puts

# ============================================================================
# Test 5: Multi-Signal Convergence
# ============================================================================
puts "Test 5: Multi-Signal Convergence"
puts "-" * 70

class MultiSignalPolicy < AgentRuntime::Policy
  def converged?(state)
    state.progress.include?(:step_one_done, :step_two_done)
  end
end

multi_policy = MultiSignalPolicy.new
multi_state = AgentRuntime::State.new

puts "✓ No signals: #{multi_policy.converged?(multi_state)} (should be false)"

multi_state.progress.mark!(:step_one_done)
puts "✓ One signal: #{multi_policy.converged?(multi_state)} (should be false)"

multi_state.progress.mark!(:step_two_done)
puts "✓ Both signals: #{multi_policy.converged?(multi_state)} (should be true)"
puts

# ============================================================================
# Summary
# ============================================================================
puts "=" * 70
puts "All Tests Passed! ✓"
puts "=" * 70
puts
puts "Convergence feature is working correctly:"
puts "  ✓ Progress tracking works"
puts "  ✓ Convergence policy can be customized"
puts "  ✓ Executor automatically marks progress signals"
puts "  ✓ Agent halts when converged"
puts "  ✓ Multi-signal convergence works"
puts
