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
#   ruby examples/complete_working_example.rb

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

                                         # Data fetcher tool
                                         "fetch_data" => lambda do |resource:, **options|
                                           {
                                             resource: resource,
                                             data: { id: 123, name: "Sample Data", options: options },
                                             fetched_at: Time.now.utc.iso8601
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
      "enum" => %w[search calculate fetch_data finish],
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
    - fetch_data: Fetch data from a resource (requires: resource name)
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

policy = AgentRuntime::Policy.new
executor = AgentRuntime::Executor.new(tool_registry: tools)
state = AgentRuntime::State.new

puts "✅ Components initialized"
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
# TEST 3: Multi-step Workflow
# ============================================================================
puts "\n📝 Test 3: Multi-step workflow - Agent#run"
puts "-" * 70

begin
  result = agent.run(initial_input: "Search for Ruby, then finish")
  puts "✅ Success!"
  puts "Result: #{result.inspect}"
  puts "Iterations: #{result[:iterations]}"
rescue AgentRuntime::MaxIterationsExceeded => e
  puts "⚠️  Max iterations exceeded: #{e.message}"
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
# rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/BlockLength
class ExampleAgentFSM < AgentRuntime::AgentFSM
  def build_tools_for_chat
    tools_hash = @tool_registry.instance_variable_get(:@tools) || {}
    return [] if tools_hash.empty?

    tools_hash.keys.map do |tool_name|
      {
        type: "function",
        function: {
          name: tool_name.to_s,
          description: case tool_name.to_s
                       when "search"
                         "Search for information. Requires 'query' parameter."
                       when "calculate"
                         "Perform calculations. Requires 'expression' parameter (e.g., '2+2')."
                       when "fetch_data"
                         "Fetch data from a resource. Requires 'resource' parameter."
                       else
                         "Tool: #{tool_name}"
                       end,
          parameters: {
            type: "object",
            properties: case tool_name.to_s
                        when "search"
                          { query: { type: "string", description: "Search query" } }
                        when "calculate"
                          { expression: { type: "string", description: "Mathematical expression" } }
                        when "fetch_data"
                          { resource: { type: "string", description: "Resource name" } }
                        else
                          {}
                        end,
            required: case tool_name.to_s
                      when "search"
                        ["query"]
                      when "calculate"
                        ["expression"]
                      when "fetch_data"
                        ["resource"]
                      else
                        []
                      end
          }
        }
      }
    end
  end
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/BlockLength
end

agent_fsm = ExampleAgentFSM.new(
  planner: planner,
  policy: policy,
  executor: executor,
  state: AgentRuntime::State.new, # Fresh state for FSM
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
  puts "✅ Success!"
  puts "Done: #{result[:done]}"
  puts "Iterations: #{result[:iterations]}"
  puts "FSM States visited: #{result[:fsm_history].map { |h| h[:to] }.uniq.length}"
  puts "Final state keys: #{result[:state].keys.join(", ")}"
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
