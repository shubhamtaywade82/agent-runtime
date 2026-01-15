# frozen_string_literal: true

# DhanHQ integration helpers for agent_runtime console
# Requires: dhan_hq gem and ollama-client examples

module DhanHQConsoleHelpers
  def check_dhanhq
    begin
      require "dhan_hq"
    rescue LoadError
      puts "❌ dhan_hq gem not installed"
      puts "   Install with: gem install dhan_hq"
      puts "   Or add to Gemfile: gem 'dhan_hq'"
      return false
    end

    begin
      DhanHQ.configure_with_env
      puts "✅ DhanHQ configured"
      true
    rescue StandardError => e
      puts "❌ DhanHQ configuration error: #{e.message}"
      puts "   Make sure CLIENT_ID and ACCESS_TOKEN are set in ENV"
      false
    end
  end

  def load_dhanhq_tools
    # Load DhanHQ tools from ollama-client examples
    tools_path = "/home/nemesis/project/ollama-client/examples/dhanhq_tools.rb"
    unless File.exist?(tools_path)
      puts "❌ DhanHQ tools not found at: #{tools_path}"
      puts "   Make sure ollama-client examples are available"
      return false
    end

    begin
      require tools_path
      true
    rescue LoadError => e
      puts "❌ Failed to load DhanHQ tools: #{e.message}"
      puts "   Make sure dhan_hq gem is installed"
      false
    rescue StandardError => e
      puts "❌ Error loading DhanHQ tools: #{e.message}"
      false
    end
  end

  def build_dhanhq_tool_registry
    return nil unless defined?(DhanHQDataTools)

    AgentRuntime::ToolRegistry.new({
      "find_instrument" => ->(**args) {
        DhanHQDataTools.find_instrument(**compact_kwargs(symbol: args[:symbol]))
      },
      "get_market_quote" => ->(**args) {
        DhanHQDataTools.get_market_quote(**compact_kwargs(
          exchange_segment: args[:exchange_segment],
          symbol: args[:symbol],
          security_id: args[:security_id]
        ))
      },
      "get_live_ltp" => ->(**args) {
        DhanHQDataTools.get_live_ltp(**compact_kwargs(
          exchange_segment: args[:exchange_segment],
          symbol: args[:symbol],
          security_id: args[:security_id]
        ))
      },
      "get_market_depth" => ->(**args) {
        DhanHQDataTools.get_market_depth(**compact_kwargs(
          exchange_segment: args[:exchange_segment],
          symbol: args[:symbol],
          security_id: args[:security_id]
        ))
      },
      "get_historical_data" => ->(**args) {
        normalized_security_id = args[:security_id] ? args[:security_id].to_i : nil
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
      "get_expiry_list" => ->(**args) {
        normalized_security_id = args[:security_id] ? args[:security_id].to_i : nil
        DhanHQDataTools.get_expiry_list(**compact_kwargs(
          exchange_segment: args[:exchange_segment],
          symbol: args[:symbol],
          security_id: normalized_security_id
        ))
      },
      "get_option_chain" => ->(**args) {
        normalized_security_id = args[:security_id] ? args[:security_id].to_i : nil
        normalized_strikes_count = (args[:strikes_count] || 5).to_i
        DhanHQDataTools.get_option_chain(**compact_kwargs(
          exchange_segment: args[:exchange_segment],
          symbol: args[:symbol],
          security_id: normalized_security_id,
          expiry: args[:expiry],
          strikes_count: normalized_strikes_count
        ))
      },
      "get_expired_options_data" => ->(**args) {
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
  end

  def build_dhanhq_agent(model: "llama3.1:8b")
    require "ollama_client"

    unless check_dhanhq
      puts "\n💡 Tip: DhanHQ integration requires the dhan_hq gem"
      return nil
    end

    unless load_dhanhq_tools
      puts "\n💡 Tip: Make sure ollama-client examples are available"
      return nil
    end

    tools = build_dhanhq_tool_registry
    unless tools
      puts "\n💡 Tip: Failed to build DhanHQ tool registry"
      return nil
    end

    config = Ollama::Config.new
    config.model = model
    client = Ollama::Client.new(config: config)

    schema = {
      "type" => "object",
      "required" => ["action", "params", "confidence"],
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

    AgentRuntime::Agent.new(
      planner: planner,
      executor: AgentRuntime::Executor.new(tool_registry: tools),
      policy: AgentRuntime::Policy.new,
      state: AgentRuntime::State.new,
      audit_log: AgentRuntime::AuditLog.new
    )
  end

  def test_dhanhq_agent(agent, input)
    puts "\n" + "=" * 60
    puts "Testing DhanHQ Agent: #{input}"
    puts "=" * 60

    if agent.nil?
      puts "\n❌ Agent is nil. Make sure build_dhanhq_agent succeeded."
      puts "   Check that dhan_hq gem is installed and DhanHQ is configured."
      return nil
    end

    begin
      result = agent.step(input: input)
      puts "\n✅ Success!"
      puts "Result: #{result.inspect}"
      puts "\nState: #{agent.instance_variable_get(:@state).snapshot.inspect}"
      result
    rescue Ollama::RetryExhaustedError => e
      puts "\n❌ Ollama server error: #{e.message}"
      puts "Make sure Ollama server is running: ollama serve"
      nil
    rescue Ollama::NotFoundError => e
      puts "\n❌ Model not found: #{e.message}"
      nil
    rescue AgentRuntime::PolicyViolation => e
      puts "\n❌ Policy violation: #{e.message}"
      nil
    rescue StandardError => e
      puts "\n❌ Error: #{e.class}: #{e.message}"
      puts e.backtrace.first(5)
      nil
    end
  end

  private

  def compact_kwargs(kwargs)
    kwargs.reject { |_, value| value.nil? || value == "" }
  end
end

# Include in main scope for console use
include DhanHQConsoleHelpers if defined?(IRB)
