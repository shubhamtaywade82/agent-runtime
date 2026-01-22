#!/usr/bin/env ruby
# frozen_string_literal: true

# Complete Working Example for AgentRuntime
#
# This example demonstrates a complete, working implementation of AgentRuntime
# that users can run to understand how the gem works.
#
# Prerequisites:
#   1. Ollama server running: `ollama serve`
#   2. A model available (e.g., `ollama pull llama3.1:8b`)
#
# Usage:
#   bundle exec ruby examples/complete_working_example.rb
#   Note: Use bundle exec to ensure you're using the local development version
#         with all features (including progress tracking and convergence)

require "agent_runtime"
require "ollama_client"

puts "=" * 70
puts "AgentRuntime Complete Working Example"
puts "=" * 70
puts

# ============================================================================
# STEP 1: Define Tools
# ============================================================================
puts "📦 Step 1: Setting up tools..."

tools = AgentRuntime::ToolRegistry.new({
                                         # Simple search tool
                                         "search" => lambda do |query:|
                                           {
                                             results: [
                                               { title: "Result 1 for #{query}", url: "https://example.com/1" },
                                               { title: "Result 2 for #{query}", url: "https://example.com/2" }
                                             ],
                                             count: 2
                                           }
                                         end,

                                         # Calculator tool
                                         "calculate" => lambda do |expression:|
                                           result = eval(expression) # rubocop:disable Security/Eval
                                           { result: result, expression: expression }
                                         end,

                                         # Get time tool (no parameters needed)
                                         "get_time" => lambda do |**_kwargs|
                                           {
                                             current_time: Time.now.utc.iso8601,
                                             timezone: "UTC"
                                           }
                                         end
                                       })

puts "✅ Tools registered: #{tools.instance_variable_get(:@tools).keys.join(", ")}"
puts

# ============================================================================
# STEP 2: Configure Ollama Client
# ============================================================================
puts "🤖 Step 2: Configuring Ollama client..."

begin
  config = Ollama::Config.new
  config.model = "llama3.1:8b" # Change to your available model
  client = Ollama::Client.new(config: config)

  # Test connection
  client.list_models
  puts "✅ Ollama client configured (model: #{config.model})"
rescue StandardError => e
  puts "❌ Error connecting to Ollama: #{e.message}"
  puts "   Make sure Ollama is running: ollama serve"
  puts "   And you have a model: ollama pull llama3.1:8b"
  exit 1
end
puts

# ============================================================================
# STEP 3: Define Schema for Structured Output
# ============================================================================
puts "📋 Step 3: Defining decision schema..."

schema = {
  "type" => "object",
  "required" => %w[action params],
  "properties" => {
    "action" => {
      "type" => "string",
      "enum" => %w[search calculate get_time finish],
      "description" => "The action to execute"
    },
    "params" => {
      "type" => "object",
      "additionalProperties" => true,
      "description" => "Parameters for the action"
    },
    "confidence" => {
      "type" => "number",
      "minimum" => 0,
      "maximum" => 1,
      "description" => "Confidence level (0.0 to 1.0)"
    }
  }
}

puts "✅ Schema defined with actions: #{schema["properties"]["action"]["enum"].join(", ")}"
puts

# ============================================================================
# STEP 4: Create Prompt Builder
# ============================================================================
puts "✍️  Step 4: Creating prompt builder..."

prompt_builder = lambda do |input:, state:|
  <<~PROMPT
    You are a helpful assistant that decides what actions to take.

    User Request: #{input}

    Current State: #{state.to_json}

    Available Actions:
    - search: Search for information (requires: query)
    - calculate: Perform calculations (requires: expression like "2+2" or "10*5")
    - get_time: Get current time (no parameters needed)
    - finish: Complete the task

    Respond with a JSON object:
    {
      "action": "one of the available actions",
      "params": { "key": "value" },
      "confidence": 0.9
    }
  PROMPT
end

puts "✅ Prompt builder created"
puts

# ============================================================================
# STEP 5: Create Planner
# ============================================================================
puts "🧠 Step 5: Creating planner..."

planner = AgentRuntime::Planner.new(
  client: client,
  schema: schema,
  prompt_builder: prompt_builder
)

puts "✅ Planner created"
puts

# ============================================================================
# STEP 6: Create Policy, Executor, and State
# ============================================================================
puts "⚙️  Step 6: Setting up policy, executor, and state..."

# Create a convergence policy that halts after a tool is called
# This demonstrates how to prevent infinite loops
class ConvergentPolicy < AgentRuntime::Policy
  def converged?(state)
    # Converge when a tool has been called (prevents infinite exploration)
    # Check if progress tracking is available (backward compatibility)
    return false unless state.respond_to?(:progress)

    state.progress.include?(:tool_called)
  end
end

policy = ConvergentPolicy.new
executor = AgentRuntime::Executor.new(tool_registry: tools)
state = AgentRuntime::State.new

puts "✅ Components initialized (with convergence policy)"
puts

# ============================================================================
# STEP 7: Create Agent
# ============================================================================
puts "🤖 Step 7: Creating agent..."

agent = AgentRuntime::Agent.new(
  planner: planner,
  policy: policy,
  executor: executor,
  state: state,
  audit_log: AgentRuntime::AuditLog.new
)

puts "✅ Agent created"
puts
puts "=" * 70
puts "Testing Agent#step - Single Step Execution"
puts "=" * 70
puts

# ============================================================================
# TEST 1: Single Step with Search
# ============================================================================
puts "\n📝 Test 1: Single step - Search action"
puts "-" * 70

begin
  result = agent.step(input: "Search for Ruby programming tutorials")
  puts "✅ Success!"
  puts "Result: #{result.inspect}"
  puts "State after step: #{state.snapshot.keys.join(", ")}"
  if state.respond_to?(:progress)
    puts "Progress signals: #{state.progress.signals.inspect}"
    puts "   (Convergence policy will halt agent when :tool_called signal is present)"
  end
rescue AgentRuntime::PolicyViolation => e
  puts "❌ Policy violation: #{e.message}"
rescue AgentRuntime::ExecutionError => e
  puts "❌ Execution error: #{e.message}"
rescue StandardError => e
  puts "❌ Error: #{e.class}: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

puts

# ============================================================================
# TEST 2: Single Step with Calculation
# ============================================================================
puts "\n📝 Test 2: Single step - Calculate action"
puts "-" * 70

begin
  result = agent.step(input: "Calculate 15 * 23")
  puts "✅ Success!"
  puts "Result: #{result.inspect}"
rescue StandardError => e
  puts "❌ Error: #{e.class}: #{e.message}"
end

puts

# ============================================================================
# TEST 3: Multi-step Workflow with Convergence
# ============================================================================
puts "\n📝 Test 3: Multi-step workflow - Agent#run with convergence"
puts "-" * 70

begin
  # Create a fresh state for this demo
  demo_state = AgentRuntime::State.new

  # Check if progress tracking is available
  has_progress = demo_state.respond_to?(:progress)

  if has_progress
    puts "   Using convergence policy: will halt after tool is called"
  else
    puts "   Progress tracking not available - using max_iterations safety limit"
  end

  # Use lower max_iterations for demo purposes
  demo_agent = AgentRuntime::Agent.new(
    planner: planner,
    policy: policy,
    executor: executor,
    state: demo_state,
    max_iterations: 5 # Increased to allow tool call + convergence check
  )

  result = demo_agent.run(initial_input: "Get the current time")

  # Check if agent converged successfully
  # Convergence is detected by: progress signals OR low iteration count OR done flag
  converged_by_policy = has_progress && demo_state.progress.include?(:tool_called)
  iterations = result[:iterations] || 0
  has_result_data = result.is_a?(Hash) && (result[:current_time] || result[:done] || result.keys.any?)
  completed = result[:done] || converged_by_policy || (has_result_data && iterations < 5)

  if completed
    puts "✅ Success! Agent completed"
    puts "Result: #{result.inspect}"
    puts "Iterations: #{iterations}"
    if has_progress
      puts "Progress signals: #{demo_state.progress.signals.inspect}"
      if converged_by_policy
        puts "   ✓ Convergence policy halted agent after tool was called"
      elsif result[:done]
        puts "   (Agent completed via finish action)"
      else
        puts "   (Agent completed successfully)"
      end
    end
  else
    puts "⚠️  Agent did not complete (may have hit max iterations)"
    puts "Result: #{result.inspect}"
    puts "Iterations: #{iterations}"
    if has_progress
      puts "Progress signals: #{demo_state.progress.signals.inspect}"
      puts "   (If progress tracking is available, convergence should prevent this)"
    else
      puts "   Run with 'bundle exec' to enable convergence-based halting"
    end
  end
rescue AgentRuntime::MaxIterationsExceeded => e
  puts "⚠️  Max iterations exceeded: #{e.message}"
  if demo_state.respond_to?(:progress)
    puts "   Progress signals: #{demo_state.progress.signals.inspect}"
    puts "   (Note: If progress tracking is available, convergence should prevent this)"
  else
    puts "   (This demonstrates the max_iterations safety mechanism)"
    puts "   Run with 'bundle exec' to enable convergence-based halting"
  end
rescue StandardError => e
  puts "❌ Error: #{e.class}: #{e.message}"
end

puts
puts "=" * 70
puts "Testing AgentFSM - Full FSM Workflow"
puts "=" * 70
puts

# ============================================================================
# STEP 8: Create AgentFSM
# ============================================================================
puts "\n🤖 Step 8: Creating AgentFSM..."

# For AgentFSM, we need to override build_tools_for_chat to provide proper tool schemas
class ExampleAgentFSM < AgentRuntime::AgentFSM
  def build_tools_for_chat
    tools_hash = @tool_registry.instance_variable_get(:@tools) || {}
    return [] if tools_hash.empty?

    tools_hash.keys.map { |tool_name| build_tool_schema(tool_name) }
  end

  private

  def build_tool_schema(tool_name)
    {
      type: "function",
      function: {
        name: tool_name.to_s,
        description: tool_description(tool_name),
        parameters: tool_parameters(tool_name)
      }
    }
  end

  def tool_description(tool_name)
    TOOL_DESCRIPTIONS.fetch(tool_name.to_s, "Tool: #{tool_name}")
  end

  def tool_parameters(tool_name)
    {
      type: "object",
      properties: tool_properties(tool_name),
      required: tool_required_params(tool_name)
    }
  end

  def tool_properties(tool_name)
    TOOL_PROPERTIES.fetch(tool_name.to_s, {})
  end

  def tool_required_params(tool_name)
    TOOL_REQUIRED.fetch(tool_name.to_s, [])
  end

  TOOL_DESCRIPTIONS = {
    "search" => "Search for information. Requires 'query' parameter.",
    "calculate" => "Perform calculations. Requires 'expression' parameter (e.g., '2+2').",
    "get_time" => "Get current time. No parameters required."
  }.freeze

  TOOL_PROPERTIES = {
    "search" => { query: { type: "string", description: "Search query" } },
    "calculate" => { expression: { type: "string", description: "Mathematical expression" } },
    "get_time" => {}
  }.freeze

  TOOL_REQUIRED = {
    "search" => ["query"],
    "calculate" => ["expression"],
    "get_time" => []
  }.freeze
end

# Create a fresh state for FSM
fsm_state = AgentRuntime::State.new

agent_fsm = ExampleAgentFSM.new(
  planner: planner,
  policy: policy,
  executor: executor,
  state: fsm_state, # Fresh state for FSM
  tool_registry: tools,
  audit_log: AgentRuntime::AuditLog.new,
  max_iterations: 10
)

puts "✅ AgentFSM created"
puts

# ============================================================================
# TEST 4: AgentFSM Workflow
# ============================================================================
puts "\n📝 Test 4: AgentFSM full workflow"
puts "-" * 70

begin
  result = agent_fsm.run(initial_input: "Search for information about Ruby agents")

  if result.nil?
    puts "✅ FSM completed (halted before finalize)"
    puts "FSM is in terminal state: #{agent_fsm.fsm.terminal?}"
    puts "Final FSM state: #{agent_fsm.fsm.state_name}"
  elsif result.is_a?(Hash)
    puts "✅ Success!"
    puts "Done: #{result[:done]}"
    puts "Iterations: #{result[:iterations]}" if result[:iterations]
    puts "FSM States visited: #{result[:fsm_history].map { |h| h[:to] }.uniq.length}" if result[:fsm_history]
    puts "Final state keys: #{result[:state].keys.join(", ")}" if result[:state]
    if fsm_state.respond_to?(:progress)
      puts "Progress signals: #{fsm_state.progress.signals.inspect}"
      puts "   (Note: FSM converged when policy indicated completion)"
    else
      puts "   (Note: FSM completed workflow successfully)"
    end
  else
    puts "⚠️  Unexpected result type: #{result.class}"
  end
rescue AgentRuntime::ExecutionError => e
  puts "❌ Execution error: #{e.message}"
rescue StandardError => e
  puts "❌ Error: #{e.class}: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

puts
puts "=" * 70
puts "Example Complete!"
puts "=" * 70
puts
puts "Next steps:"
puts "  1. Customize tools for your domain"
puts "  2. Adjust schema and prompts for your use case"
puts "  3. Implement custom Policy for your safety requirements"
puts "  4. See README.md and examples/ for more patterns"
puts
