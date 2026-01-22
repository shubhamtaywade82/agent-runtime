#!/usr/bin/env ruby
# frozen_string_literal: true

# DhanHQ integration example for agent_runtime
# Tests agent_runtime with real Indian market data via DhanHQ APIs

require "agent_runtime"
require "ollama_client"

# Try to require dhan_hq gem (may fail if dependencies missing)
begin
  require "dhan_hq"
rescue LoadError => e
  puts "❌ DhanHQ gem or dependencies not available"
  puts "   Error: #{e.message}"
  puts ""
  puts "   To use this example, install:"
  puts "   - gem install dhan_hq"
  puts "   - gem install technical-analysis (or ruby-technical-analysis)"
  puts ""
  puts "   Or add to Gemfile:"
  puts '   gem "DhanHQ", git: "https://github.com/shubhamtaywade82/dhanhq-client.git"'
  puts '   gem "technical-analysis"'
  exit 1
end

# Load DhanHQ tools from ollama-client examples
# Set DHANHQ_TOOLS_PATH environment variable to point to dhanhq_tools.rb
tools_path = ENV.fetch("DHANHQ_TOOLS_PATH", nil)

# Try common default locations if not set
if tools_path.nil? || !File.exist?(tools_path)
  default_paths = [
    "/home/nemesis/project/ollama-client/examples/dhanhq_tools.rb",
    "../ollama-client/examples/dhanhq_tools.rb",
    "../../ollama-client/examples/dhanhq_tools.rb",
    File.expand_path("~/project/ollama-client/examples/dhanhq_tools.rb"),
    File.expand_path("~/ollama-client/examples/dhanhq_tools.rb")
  ]

  tools_path = default_paths.find { |path| File.exist?(path) }
end

unless tools_path && File.exist?(tools_path)
  puts "❌ DhanHQ tools not found"
  puts "   Set DHANHQ_TOOLS_PATH environment variable to point to dhanhq_tools.rb"
  puts "   Example: export DHANHQ_TOOLS_PATH=/path/to/ollama-client/examples/dhanhq_tools.rb"
  puts ""
  puts "   Or place dhanhq_tools.rb in a standard location:"
  puts "   - /home/nemesis/project/ollama-client/examples/dhanhq_tools.rb"
  puts "   - ../ollama-client/examples/dhanhq_tools.rb (relative to this file)"
  exit 1
end

puts "✅ Loading DhanHQ tools from: #{tools_path}"
require tools_path

# Configure DhanHQ
begin
  DhanHQ.configure_with_env
  puts "✅ DhanHQ configured"
rescue StandardError => e
  puts "❌ DhanHQ configuration error: #{e.message}"
  puts "   Make sure CLIENT_ID and ACCESS_TOKEN are set in ENV"
  exit 1
end

# Helper to remove nil/empty values from kwargs
def compact_kwargs(kwargs)
  kwargs.reject { |_, value| value.nil? || value == "" }
end

# 1. Set up DhanHQ tools
tools = AgentRuntime::ToolRegistry.new({
                                         "find_instrument" => lambda { |**args|
                                           DhanHQDataTools.find_instrument(**compact_kwargs(symbol: args[:symbol]))
                                         },
                                         "get_market_quote" => lambda { |**args|
                                           DhanHQDataTools.get_market_quote(**compact_kwargs(
                                             exchange_segment: args[:exchange_segment],
                                             symbol: args[:symbol],
                                             security_id: args[:security_id]
                                           ))
                                         },
                                         "get_live_ltp" => lambda { |**args|
                                           DhanHQDataTools.get_live_ltp(**compact_kwargs(
                                             exchange_segment: args[:exchange_segment],
                                             symbol: args[:symbol],
                                             security_id: args[:security_id]
                                           ))
                                         },
                                         "get_market_depth" => lambda { |**args|
                                           DhanHQDataTools.get_market_depth(**compact_kwargs(
                                             exchange_segment: args[:exchange_segment],
                                             symbol: args[:symbol],
                                             security_id: args[:security_id]
                                           ))
                                         },
                                         "get_historical_data" => lambda { |**args|
                                           normalized_security_id = args[:security_id]&.to_i
                                           DhanHQDataTools.get_historical_data(**compact_kwargs(
                                             exchange_segment: args[:exchange_segment],
                                             symbol: args[:symbol],
                                             security_id: normalized_security_id,
                                             from_date: args[:from_date],
                                             to_date: args[:to_date],
                                             interval: args[:interval],
                                             expiry_code: args[:expiry_code],
                                             calculate_indicators: args[:calculate_indicators] || false
                                           ))
                                         },
                                         "get_expiry_list" => lambda { |**args|
                                           normalized_security_id = args[:security_id]&.to_i
                                           DhanHQDataTools.get_expiry_list(**compact_kwargs(
                                             exchange_segment: args[:exchange_segment],
                                             symbol: args[:symbol],
                                             security_id: normalized_security_id
                                           ))
                                         },
                                         "get_option_chain" => lambda { |**args|
                                           normalized_security_id = args[:security_id]&.to_i
                                           normalized_strikes_count = (args[:strikes_count] || 5).to_i
                                           DhanHQDataTools.get_option_chain(**compact_kwargs(
                                             exchange_segment: args[:exchange_segment],
                                             symbol: args[:symbol],
                                             security_id: normalized_security_id,
                                             expiry: args[:expiry],
                                             strikes_count: normalized_strikes_count
                                           ))
                                         },
                                         "get_expired_options_data" => lambda { |**args|
                                           DhanHQDataTools.get_expired_options_data(**compact_kwargs(
                                             exchange_segment: args[:exchange_segment],
                                             expiry_date: args[:expiry_date],
                                             symbol: args[:symbol],
                                             security_id: args[:security_id],
                                             interval: args[:interval],
                                             instrument: args[:instrument],
                                             expiry_flag: args[:expiry_flag],
                                             expiry_code: args[:expiry_code],
                                             strike: args[:strike],
                                             drv_option_type: args[:drv_option_type],
                                             required_data: args[:required_data]
                                           ))
                                         }
                                       })

# 2. Configure Ollama client
config = Ollama::Config.new
config.model = ENV.fetch("OLLAMA_MODEL", "llama3.1:8b")
client = Ollama::Client.new(config: config)

# 3. Create planner with DhanHQ-specific schema
schema = {
  "type" => "object",
  "required" => %w[action params confidence],
  "properties" => {
    "action" => {
      "type" => "string",
      "enum" => %w[find_instrument get_market_quote get_live_ltp get_market_depth
                   get_historical_data get_expiry_list get_option_chain
                   get_expired_options_data finish],
      "description" => "The DhanHQ API action to execute"
    },
    "params" => {
      "type" => "object",
      "additionalProperties" => true,
      "description" => "Parameters for the DhanHQ API call"
    },
    "confidence" => {
      "type" => "number",
      "minimum" => 0,
      "maximum" => 1,
      "description" => "Confidence level in this decision"
    }
  }
}

planner = AgentRuntime::Planner.new(
  client: client,
  schema: schema,
  prompt_builder: lambda { |input:, state:|
    <<~PROMPT
      You are a market data assistant for Indian markets using DhanHQ APIs.

      User request: #{input}

      Current state: #{state.to_json}

      Available DhanHQ API actions:
      - find_instrument: Find instrument details by symbol (returns exchange_segment, security_id)
      - get_market_quote: Get full market quote (OHLC, depth, volume)
      - get_live_ltp: Get last traded price (fastest for current price)
      - get_market_depth: Get full market depth (bid/ask levels, order book)
      - get_historical_data: Get historical OHLCV data (daily or intraday)
      - get_expiry_list: Get available expiry dates for options
      - get_option_chain: Get option chain for a specific expiry
      - get_expired_options_data: Get historical expired options data
      - finish: Complete the task

      Exchange segments: NSE_EQ, NSE_FNO, NSE_CURRENCY, BSE_EQ, BSE_FNO, BSE_CURRENCY, MCX_COMM, IDX_I

      Common workflow:
      1. If you only have a symbol, call find_instrument first to get exchange_segment and security_id
      2. Then use those values for subsequent API calls
      3. For options, use get_expiry_list first, then get_option_chain with the expiry date

      Respond with a JSON object containing:
      - action: one of the available actions
      - params: parameters needed for the action (symbol, exchange_segment, security_id, dates, etc.)
      - confidence: your confidence level (0.0 to 1.0)
    PROMPT
  }
)

# 4. Create convergence policy (prevents infinite loops)
# For multi-step workflows, converge when we have the final result
class ConvergentPolicy < AgentRuntime::Policy
  def converged?(state)
    # Check if progress tracking is available (backward compatibility)
    return false unless state.respond_to?(:progress)

    snapshot = state.snapshot

    # Converge when we have actual market data (LTP, quote, etc.)
    # This allows multi-step workflows: find_instrument -> get_live_ltp/get_market_quote
    has_market_data = snapshot[:ltp] ||
                      snapshot[:last_traded_price] ||
                      snapshot[:quote] ||
                      snapshot[:market_quote] ||
                      (snapshot[:result] && (snapshot[:result][:ltp] || snapshot[:result][:quote]))

    # Also converge if we've called multiple tools (likely completed workflow)
    tool_call_count = state.progress.signals.count { |s| s == :tool_called }
    has_market_data || tool_call_count >= 2
  end
end

# 5. Create agent
agent_state = AgentRuntime::State.new
agent = AgentRuntime::Agent.new(
  planner: planner,
  executor: AgentRuntime::Executor.new(tool_registry: tools),
  policy: ConvergentPolicy.new,
  state: agent_state,
  audit_log: AgentRuntime::AuditLog.new
)

# 5. Test examples
puts "=" * 60
puts "DhanHQ + agent_runtime Integration Test"
puts "=" * 60
puts

test_cases = [
  "Get LTP of RELIANCE",
  "Find instrument details for NIFTY",
  "Get market quote for TCS on NSE_EQ"
]

test_cases.each do |test_input|
  puts "\n#{"-" * 60}"
  puts "Test: #{test_input}"
  puts "-" * 60

  # Create a fresh state for each test to avoid state pollution
  test_state = AgentRuntime::State.new
  test_agent = AgentRuntime::Agent.new(
    planner: planner,
    executor: AgentRuntime::Executor.new(tool_registry: tools),
    policy: ConvergentPolicy.new,
    state: test_state,
    audit_log: AgentRuntime::AuditLog.new,
    max_iterations: 10 # Allow multiple steps to complete the workflow
  )

  begin
    # Use agent.run() to allow multi-step execution until convergence
    # This enables workflows like: find_instrument -> get_live_ltp
    result = test_agent.run(initial_input: test_input)

    puts "\n✅ Success!"
    puts "Result: #{result.inspect}"
    puts "Iterations: #{result[:iterations] || "N/A"}"
    if test_state.respond_to?(:progress)
      puts "Progress signals: #{test_state.progress.signals.inspect}"
      tool_count = test_state.progress.signals.count { |s| s == :tool_called }
      puts "   (Agent executed #{tool_count} tool(s) to complete the task)"
    end
    puts "Final state keys: #{test_state.snapshot.keys.join(", ")}"
  rescue AgentRuntime::MaxIterationsExceeded => e
    puts "\n⚠️  Max iterations exceeded: #{e.message}"
    puts "   (Agent may need more steps or different prompt to complete task)"
    puts "Progress signals: #{test_state.progress.signals.inspect}" if test_state.respond_to?(:progress)
  rescue Ollama::RetryExhaustedError => e
    puts "\n❌ Ollama server error: #{e.message}"
    puts "Make sure Ollama server is running: ollama serve"
  rescue Ollama::NotFoundError => e
    puts "\n❌ Model not found: #{e.message}"
  rescue AgentRuntime::PolicyViolation => e
    puts "\n❌ Policy violation: #{e.message}"
  rescue StandardError => e
    puts "\n❌ Error: #{e.class}: #{e.message}"
    puts e.backtrace.first(5)
  end

  sleep(1) # Rate limiting between requests
end

puts "\n#{"=" * 60}"
puts "Testing complete!"
puts "=" * 60
