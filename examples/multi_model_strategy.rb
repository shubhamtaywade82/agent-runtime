#!/usr/bin/env ruby
# frozen_string_literal: true

# Multi-Model Strategy Example for AgentRuntime
#
# This example demonstrates how to use different Ollama models for different
# cognitive states in an agentic workflow. Based on production-grade patterns
# for trading systems.
#
# STATE → MODEL MAPPING:
# - PLAN (Reason):     llama3.1:8b          (Core reasoning, temp: 0.1)
# - DECIDE (Validate): mistral:7b-instruct  (Strict validation, temp: 0.0)
# - FINALIZE (Explain): llama3.2:3b        (Human explanation, temp: 0.3)
#
# Prerequisites (models available in your Ollama server):
#   - llama3.1:8b
#   - mistral:7b-instruct
#   - llama3.2:3b
#
# Check available models: docker exec -it ollama-server ollama list

require "agent_runtime"
require "ollama_client"

# Model names - can be overridden via environment variables
# Defaults use models available in your Ollama server
REASONING_MODEL = ENV.fetch("REASONING_MODEL", "llama3.1:8b")
VALIDATION_MODEL = ENV.fetch("VALIDATION_MODEL", "mistral:7b-instruct") # Strict validation model
EXPLANATION_MODEL = ENV.fetch("EXPLANATION_MODEL", "llama3.2:3b")

puts "=" * 70
puts "Multi-Model Strategy Example"
puts "Different models for different cognitive states"
puts "=" * 70
puts
puts "💡 Tip: Check your available models with: ollama list"
puts "   Current defaults:"
puts "   - Reasoning:   #{REASONING_MODEL}"
puts "   - Validation:  #{VALIDATION_MODEL}"
puts "   - Explanation: #{EXPLANATION_MODEL}"
puts
puts "   To use different models, set environment variables:"
puts "   REASONING_MODEL=llama3.1:8b \\"
puts "   VALIDATION_MODEL=qwen2.5-coder:7b \\"
puts "   EXPLANATION_MODEL=llama3.2:3b \\"
puts "   ruby examples/multi_model_strategy.rb"
puts

# ============================================================================
# STEP 1: Create Multiple Model Clients
# ============================================================================
puts "📦 Step 1: Initializing multiple Ollama models..."

# NOTE: We need separate clients for different temperature settings
# because client.generate() doesn't accept temperature as a parameter
# (it only uses @config.temperature). However, client.chat() does accept
# options: { temperature: X }, so we can share the client for chat calls.

reasoning_config = Ollama::Config.new
reasoning_config.temperature = 0.1 # Low temperature for reasoning
reasoning_client = Ollama::Client.new(config: reasoning_config)

validation_config = Ollama::Config.new
validation_config.temperature = 0.0 # Absolute determinism for validation
validation_client = Ollama::Client.new(config: validation_config)

# Explanation client can be shared since we'll pass temperature via options
explanation_client = Ollama::Client.new

puts "✅ Models configured:"
puts "   - Reasoning:   #{REASONING_MODEL}"
puts "   - Validation:  #{VALIDATION_MODEL}"
puts "   - Explanation: #{EXPLANATION_MODEL}"

# Quick connection test
puts
puts "🔍 Testing Ollama connection..."
begin
  reasoning_client.list_models
  puts "   ✓ Ollama accessible"
rescue StandardError => e
  puts "   ✗ Error: #{e.message}"
  puts
  puts "💡 Available models: Run 'docker exec -it ollama-server ollama list' to see what you have"
  puts "   Pull missing models with:"
  puts "     ollama pull #{REASONING_MODEL}"
  puts "     ollama pull #{VALIDATION_MODEL}"
  puts "     ollama pull #{EXPLANATION_MODEL}"
  exit 1
end
puts

# ============================================================================
# STEP 2: Define State-Specific Schemas
# ============================================================================
puts "📋 Step 2: Defining schemas for each state..."

# Schema for PLAN state (reasoning)
reasoning_schema = {
  "type" => "object",
  "required" => %w[market_bias regime directional_allowance confidence],
  "properties" => {
    "market_bias" => {
      "type" => "string",
      "enum" => %w[bullish bearish neutral],
      "description" => "Inferred market bias from SMC + AVRZ data"
    },
    "regime" => {
      "type" => "string",
      "enum" => %w[trending ranging volatile],
      "description" => "Current market regime"
    },
    "directional_allowance" => {
      "type" => "object",
      "properties" => {
        "call" => { "type" => "boolean" },
        "put" => { "type" => "boolean" }
      },
      "description" => "Which directions are allowed"
    },
    "confidence" => {
      "type" => "number",
      "minimum" => 0,
      "maximum" => 1
    }
  }
}

# Schema for DECIDE state (validation)
validation_schema = {
  "type" => "object",
  "required" => %w[decision reason violations],
  "properties" => {
    "decision" => {
      "type" => "string",
      "enum" => %w[ALLOW BLOCK],
      "description" => "Final validation decision"
    },
    "reason" => {
      "type" => "string",
      "description" => "Reason for decision"
    },
    "violations" => {
      "type" => "array",
      "items" => { "type" => "string" },
      "description" => "List of rule violations if any"
    }
  }
}

puts "✅ Schemas defined"
puts

# ============================================================================
# STEP 3: Create State-Specific Planners
# ============================================================================
puts "🧠 Step 3: Creating planners for each cognitive state..."

# REASONING PLANNER (PLAN state)
reasoning_prompt = lambda do |input:, state:|
  <<~PROMPT
    You are a market analysis engine. Analyze the structure and infer bias.

    Market Data: #{input}

    Current State: #{state.to_json}

    TASK: Infer market_bias, regime, and directional_allowance from the data.

    Rules:
    - HTF bias ALWAYS dominates
    - Trending regime requires alignment across timeframes
    - Be conservative with directional_allowance

    Respond with JSON matching the schema.
  PROMPT
end

reasoning_planner = AgentRuntime::Planner.new(
  client: reasoning_client,
  schema: reasoning_schema,
  prompt_builder: reasoning_prompt
)

# VALIDATION PLANNER (DECIDE state)
validation_prompt = lambda do |input:, state:|
  analysis = state[:analysis] || {}
  signal = input

  <<~PROMPT
    You are a compliance officer. Your job is YES/NO validation.

    Proposed Signal: #{signal}

    Market Analysis: #{analysis.to_json}

    Rules (STRICT):
    1. If HTF bias is bearish, BLOCK all calls
    2. If HTF bias is bullish, BLOCK all puts
    3. If confidence < 0.7, BLOCK
    4. If regime is "volatile", BLOCK

    TASK: Decide ALLOW or BLOCK. List any violations.

    Be LITERAL. No creativity. No exceptions.

    Respond with JSON matching the schema.
  PROMPT
end

validation_planner = AgentRuntime::Planner.new(
  client: validation_client,
  schema: validation_schema,
  prompt_builder: validation_prompt
)

# EXPLANATION PLANNER (FINALIZE state)
# No schema needed - just text generation
explanation_planner = AgentRuntime::Planner.new(
  client: explanation_client
)

puts "✅ Planners created"
puts

# ============================================================================
# STEP 4: Define Tools
# ============================================================================
puts "⚙️  Step 4: Setting up tools..."

tools = AgentRuntime::ToolRegistry.new({
                                         # Tool for fetching market data
                                         "fetch_market_data" => lambda do |symbol:, timeframe: "1h"|
                                           {
                                             symbol: symbol,
                                             timeframe: timeframe,
                                             htf_bias: "bullish",
                                             ltf_bias: "bullish",
                                             regime: "trending",
                                             avrz_zones: [{ level: 4100, type: "resistance" }]
                                           }
                                         end,

                                         # Tool for signal validation
                                         "validate_signal" => lambda do |signal_type:, entry:, **_kwargs|
                                           {
                                             signal: signal_type,
                                             entry: entry,
                                             validated: true,
                                             timestamp: Time.now.utc.iso8601
                                           }
                                         end,

                                         # Tool for sending alert
                                         "send_alert" => lambda do |message:, **_kwargs|
                                           puts "\n📱 ALERT: #{message}"
                                           { sent: true, message: message }
                                         end
                                       })

puts "✅ Tools registered"
puts

# ============================================================================
# STEP 5: Create Multi-Model FSM Agent
# ============================================================================
puts "🤖 Step 5: Creating multi-model FSM agent..."

class MultiModelAgentFSM < AgentRuntime::AgentFSM
  attr_accessor :reasoning_planner, :validation_planner, :explanation_planner

  def initialize(reasoning_planner:, validation_planner:, explanation_planner:, **)
    @reasoning_planner = reasoning_planner
    @validation_planner = validation_planner
    @explanation_planner = explanation_planner
    super(**)
  end

  # Override PLAN state to use reasoning model
  def handle_plan
    puts "   🧠 PLAN: Using reasoning model (#{REASONING_MODEL})..."

    # NOTE: We bypass Planner#plan because it expects Decision structure (action/params/confidence)
    # Our custom schema returns domain-specific keys (market_bias, regime, etc.)
    # So we use client.generate directly with our custom schema and model: option
    # Temperature comes from the client's config (0.1 for reasoning_client)

    prompt = @reasoning_planner.instance_variable_get(:@prompt_builder).call(
      input: @messages.first[:content],
      state: @state.snapshot
    )

    client = @reasoning_planner.instance_variable_get(:@client)
    schema = @reasoning_planner.instance_variable_get(:@schema)

    analysis = client.generate(
      prompt: prompt,
      schema: schema,
      model: REASONING_MODEL
    )
    analysis = analysis.transform_keys(&:to_sym)

    @state.apply!({ analysis: analysis })

    puts "      ✓ Bias: #{analysis[:market_bias]}, Regime: #{analysis[:regime]}"

    @fsm.transition_to(AgentRuntime::FSM::STATES[:DECIDE], reason: "Analysis complete")
  rescue StandardError => e
    puts "      ✗ Error: #{e.message}"
    @fsm.transition_to(AgentRuntime::FSM::STATES[:HALT], reason: "Plan failed: #{e.message}")
  end

  # Override DECIDE state to use validation model
  def handle_decide
    puts "   ⚖️  DECIDE: Using validation model (#{VALIDATION_MODEL})..."

    # NOTE: Same as handle_plan - using client.generate directly
    # to work with our custom schema structure and pass model: option
    # Temperature comes from the client's config (0.0 for validation_client - absolute determinism)

    prompt = @validation_planner.instance_variable_get(:@prompt_builder).call(
      input: "Validate signal: CALL at 4100",
      state: @state.snapshot
    )

    client = @validation_planner.instance_variable_get(:@client)
    schema = @validation_planner.instance_variable_get(:@schema)

    decision = client.generate(
      prompt: prompt,
      schema: schema,
      model: VALIDATION_MODEL
    )
    decision = decision.transform_keys(&:to_sym)

    @state.apply!({ validation: decision })

    puts "      ✓ Decision: #{decision[:decision]}"
    puts "      ✓ Reason: #{decision[:reason]}"

    if decision[:decision] == "ALLOW"
      @fsm.transition_to(AgentRuntime::FSM::STATES[:EXECUTE], reason: "Signal validated")
    else
      @fsm.transition_to(AgentRuntime::FSM::STATES[:HALT],
                         reason: "Signal blocked: #{decision[:reason]}")
    end
  rescue StandardError => e
    puts "      ✗ Error: #{e.message}"
    @fsm.transition_to(AgentRuntime::FSM::STATES[:HALT], reason: "Validation failed")
  end

  # Override EXECUTE to avoid calling the LLM again (we already made our decision)
  def handle_execute
    puts "   🔧 EXECUTE: Signal validated, transitioning to finalize..."
    # Skip actual tool execution - we're just demonstrating the multi-model flow
    # Mark progress signal to track workflow completion
    @state.progress.mark!(:workflow_complete) if @state.respond_to?(:progress)
    # Transition to FINALIZE and immediately process it
    @fsm.transition_to(AgentRuntime::FSM::STATES[:FINALIZE], reason: "Demo complete")
    # Return the result from handle_finalize directly
    handle_finalize
  end

  # Override FINALIZE to use explanation model
  def handle_finalize
    puts "   💬 FINALIZE: Using explanation model (#{EXPLANATION_MODEL})..."

    analysis = @state.snapshot[:analysis] || {}
    validation = @state.snapshot[:validation] || {}

    # Only generate summary if we have both analysis and validation
    if analysis.empty? || validation.empty?
      puts "      ⚠️  Skipping summary (missing analysis or validation)"
      return {
        done: true,
        analysis: analysis,
        validation: validation,
        summary: "N/A - workflow halted before completion",
        iterations: @fsm.iteration_count,
        fsm_history: @fsm.history
      }
    end

    summary_prompt = <<~PROMPT
      Summarize this trading decision in 1-2 lines for Telegram:

      Analysis: #{analysis.to_json}
      Validation: #{validation.to_json}

      Be concise. No technical jargon.
    PROMPT

    # Use explanation planner with model: option and temperature in options
    summary = @explanation_planner.chat(
      messages: [{ role: "user", content: summary_prompt }],
      model: EXPLANATION_MODEL,
      options: { temperature: 0.3 }
    )

    puts "      ✓ Summary: #{summary}"

    {
      done: true,
      analysis: analysis,
      validation: validation,
      summary: summary,
      iterations: @fsm.iteration_count,
      fsm_history: @fsm.history
    }
  rescue StandardError => e
    puts "      ✗ Error in FINALIZE: #{e.class}: #{e.message}"
    puts "      Backtrace: #{e.backtrace.first(3).join("\n      ")}"
    {
      done: true,
      error: e.message,
      analysis: @state.snapshot[:analysis] || {},
      validation: @state.snapshot[:validation] || {},
      iterations: @fsm.iteration_count,
      fsm_history: @fsm.history
    }
  end

  def build_tools_for_chat
    [] # Not using tool calls in this example
  end
end

# Create convergence policy (prevents infinite loops)
class ConvergentPolicy < AgentRuntime::Policy
  def converged?(state)
    # For this demo, converge when we have both analysis and validation
    # (This example skips actual tool execution to demonstrate multi-model flow)
    return false unless state.respond_to?(:progress)

    analysis = state.snapshot[:analysis] || {}
    validation = state.snapshot[:validation] || {}

    # Converge when workflow has completed analysis and validation phases
    !analysis.empty? && !validation.empty?
  end
end

agent_state = AgentRuntime::State.new
agent = MultiModelAgentFSM.new(
  reasoning_planner: reasoning_planner,
  validation_planner: validation_planner,
  explanation_planner: explanation_planner,
  planner: reasoning_planner, # Default planner
  policy: ConvergentPolicy.new,
  executor: AgentRuntime::Executor.new(tool_registry: tools),
  state: agent_state,
  tool_registry: tools,
  max_iterations: 10
)

puts "✅ Multi-model agent created"
puts

# ============================================================================
# STEP 6: Run the Workflow
# ============================================================================
puts "=" * 70
puts "Running Multi-Model Workflow"
puts "=" * 70
puts

begin
  result = agent.run(initial_input: "Analyze market: SPY with CALL signal at 4100")

  puts
  puts "=" * 70
  puts "✅ Workflow Complete"
  puts "=" * 70
  puts

  if result.nil?
    puts "⚠️  Workflow halted (no result returned)"
    puts "FSM State: #{agent.fsm.state_name}"
    puts "Terminal: #{agent.fsm.terminal?}"
  elsif result.is_a?(Hash)
    puts "Final Result:"
    if result[:analysis]
      puts "  Market Bias: #{result[:analysis][:market_bias]}"
      puts "  Regime: #{result[:analysis][:regime]}"
    end
    puts "  Decision: #{result[:validation][:decision]}" if result[:validation]
    puts "  Summary: #{result[:summary]}" if result[:summary]
    puts
    puts "States visited: #{result[:fsm_history].map { |h| h[:to] }.join(" → ")}" if result[:fsm_history]
    if agent_state.respond_to?(:progress)
      puts "Progress signals: #{agent_state.progress.signals.inspect}"
      puts "  (Note: Agent converged when policy indicated completion)"
    end
  else
    puts "⚠️  Unexpected result type: #{result.class}"
  end
rescue AgentRuntime::ExecutionError => e
  # Check if this is a validation block (expected behavior)
  if e.message.include?("Signal blocked") || e.message.include?("violation")
    puts
    puts "=" * 70
    puts "🛡️  Validation Blocked Signal (Expected Behavior)"
    puts "=" * 70
    puts
    puts "The validation model (mistral:7b-instruct) analyzed the reasoning"
    puts "and determined the signal should be BLOCKED based on validation rules."
    puts
    puts "This is correct behavior - the multi-model strategy is working as intended:"
    puts "  1. Reasoning model analyzed the market"
    puts "  2. Validation model checked against rules"
    puts "  3. Validation model blocked the signal (preventing bad trades)"
    puts
    puts "Error details: #{e.message}"
    puts "Progress signals: #{agent_state.progress.signals.inspect}" if agent_state.respond_to?(:progress)
  else
    puts
    puts "❌ Execution Error: #{e.class}: #{e.message}"
    puts e.backtrace.first(5).join("\n")
  end
rescue StandardError => e
  puts
  puts "❌ Error: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  puts
  puts "💡 Tip: Make sure you have the required models installed:"
  puts "   Check available models: docker exec -it ollama-server ollama list"
  puts "   Or pull missing models:"
  puts "     ollama pull #{REASONING_MODEL}"
  puts "     ollama pull #{VALIDATION_MODEL}"
  puts "     ollama pull #{EXPLANATION_MODEL}"
end

puts
puts "=" * 70
puts "Key Takeaway:"
puts "  - PLAN used #{REASONING_MODEL} (reasoning)"
puts "  - DECIDE used #{VALIDATION_MODEL} (validation)"
puts "  - FINALIZE used #{EXPLANATION_MODEL} (explanation)"
puts
puts "Each model did ONE job. No overlap. No confusion."
puts "=" * 70
