# frozen_string_literal: true

# Helper methods for console testing
# Load with: require_relative "lib/console_helpers"

require "date"

module ConsoleHelpers
  def check_ollama
    require "ollama_client"
    client = Ollama::Client.new
    begin
      models = client.list_models
      puts "✅ Ollama server is running"
      puts "Available models: #{models.join(", ")}"
      client
    rescue StandardError => e
      puts "❌ Ollama server not accessible: #{e.message}"
      puts "Start with: ollama serve"
      nil
    end
  end

  def build_indian_market_agent(model: "llama3.1:8b")
    require "ollama_client"

    client = check_ollama
    return nil unless client

    # Check if DhanHQ is available
    begin
      require "dhan_hq"
    rescue LoadError
      puts "❌ dhan_hq gem not installed"
      puts "   Install with: gem install dhan_hq"
      puts "   Or add to Gemfile: gem 'dhan_hq'"
      return nil
    end

    begin
      DhanHQ.configure_with_env
      puts "✅ DhanHQ configured"
    rescue StandardError => e
      puts "❌ DhanHQ configuration error: #{e.message}"
      puts "   Make sure CLIENT_ID and ACCESS_TOKEN are set in ENV"
      return nil
    end

    # Load DhanHQ tools from ollama-client examples
    tools_path = "/home/nemesis/project/ollama-client/examples/dhanhq_tools.rb"
    unless File.exist?(tools_path)
      puts "❌ DhanHQ tools not found at: #{tools_path}"
      puts "   Make sure ollama-client examples are available"
      return nil
    end

    begin
      require tools_path
    rescue LoadError => e
      puts "❌ Failed to load DhanHQ tools: #{e.message}"
      puts "   Make sure dhan_hq gem is installed"
      return nil
    rescue StandardError => e
      puts "❌ Error loading DhanHQ tools: #{e.message}"
      return nil
    end

    return nil unless defined?(DhanHQDataTools)

    # Helper to remove nil/empty values from kwargs
    compact_kwargs = ->(kwargs) { kwargs.reject { |_, value| value.nil? || value == "" } }

    tools = AgentRuntime::ToolRegistry.new({
                                             "find_instrument" => lambda { |**args|
                                               DhanHQDataTools.find_instrument(**compact_kwargs.call(symbol: args[:symbol]))
                                             },
                                             "get_market_quote" => lambda { |**args|
                                               # Auto-detect exchange_segment if not provided but symbol is
                                               if args[:symbol] && !args[:exchange_segment] && !args[:security_id]
                                                 instrument_result = DhanHQDataTools.find_instrument(symbol: args[:symbol])
                                                 if instrument_result[:result] && !instrument_result[:error]
                                                   args[:exchange_segment] =
                                                     instrument_result[:result][:exchange_segment]
                                                   args[:security_id] = instrument_result[:result][:security_id]
                                                 end
                                               end
                                               # Default to NSE_EQ if still missing
                                               args[:exchange_segment] ||= "NSE_EQ"

                                               DhanHQDataTools.get_market_quote(**compact_kwargs.call(
                                                 exchange_segment: args[:exchange_segment],
                                                 symbol: args[:symbol],
                                                 security_id: args[:security_id]
                                               ))
                                             },
                                             "get_live_ltp" => lambda { |**args|
                                               # Auto-detect exchange_segment if not provided but symbol is
                                               if args[:symbol] && !args[:exchange_segment] && !args[:security_id]
                                                 instrument_result = DhanHQDataTools.find_instrument(symbol: args[:symbol])
                                                 if instrument_result[:result] && !instrument_result[:error]
                                                   args[:exchange_segment] =
                                                     instrument_result[:result][:exchange_segment]
                                                   args[:security_id] = instrument_result[:result][:security_id]
                                                 end
                                               end
                                               # Default to NSE_EQ if still missing
                                               args[:exchange_segment] ||= "NSE_EQ"

                                               DhanHQDataTools.get_live_ltp(**compact_kwargs.call(
                                                 exchange_segment: args[:exchange_segment],
                                                 symbol: args[:symbol],
                                                 security_id: args[:security_id]
                                               ))
                                             },
                                             "get_market_depth" => lambda { |**args|
                                               DhanHQDataTools.get_market_depth(**compact_kwargs.call(
                                                 exchange_segment: args[:exchange_segment],
                                                 symbol: args[:symbol],
                                                 security_id: args[:security_id]
                                               ))
                                             },
                                             "get_historical_data" => lambda { |**args|
                                               # Auto-detect exchange_segment if not provided but symbol is
                                               if args[:symbol] && !args[:exchange_segment] && !args[:security_id]
                                                 instrument_result = DhanHQDataTools.find_instrument(symbol: args[:symbol])
                                                 if instrument_result[:result] && !instrument_result[:error]
                                                   args[:exchange_segment] =
                                                     instrument_result[:result][:exchange_segment]
                                                   args[:security_id] = instrument_result[:result][:security_id]
                                                 end
                                               end
                                               # Default to NSE_EQ if still missing
                                               args[:exchange_segment] ||= "NSE_EQ"

                                               # Provide default dates if not specified (last 30 days)
                                               unless args[:from_date] || args[:to_date]
                                                 today = Date.today
                                                 args[:to_date] ||= today.strftime("%Y-%m-%d")
                                                 args[:from_date] ||= (today - 30).strftime("%Y-%m-%d")
                                               end

                                               normalized_security_id = args[:security_id] ? args[:security_id].to_i : nil
                                               DhanHQDataTools.get_historical_data(**compact_kwargs.call(
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
                                               # Auto-detect exchange_segment if not provided but symbol is
                                               if args[:symbol] && !args[:exchange_segment] && !args[:security_id]
                                                 instrument_result = DhanHQDataTools.find_instrument(symbol: args[:symbol])
                                                 if instrument_result[:result] && !instrument_result[:error]
                                                   args[:exchange_segment] =
                                                     instrument_result[:result][:exchange_segment]
                                                   args[:security_id] = instrument_result[:result][:security_id]
                                                 end
                                               end
                                               # For indices like NIFTY, use IDX_I; for stocks, try NSE_FNO first
                                               if args[:symbol] && !args[:exchange_segment]
                                                 symbol_up = args[:symbol].to_s.upcase
                                                 args[:exchange_segment] = if %w[NIFTY BANKNIFTY FINNIFTY MIDCPNIFTY SENSEX BANKEX].include?(symbol_up)
                                                                              "IDX_I"
                                                                            else
                                                                              "NSE_FNO"
                                                                            end
                                               end

                                               normalized_security_id = args[:security_id] ? args[:security_id].to_i : nil
                                               DhanHQDataTools.get_expiry_list(**compact_kwargs.call(
                                                 exchange_segment: args[:exchange_segment],
                                                 symbol: args[:symbol],
                                                 security_id: normalized_security_id
                                               ))
                                             },
                                             "get_option_chain" => lambda { |**args|
                                               # Auto-detect exchange_segment if not provided but symbol is
                                               if args[:symbol] && !args[:exchange_segment] && !args[:security_id]
                                                 instrument_result = DhanHQDataTools.find_instrument(symbol: args[:symbol])
                                                 if instrument_result[:result] && !instrument_result[:error]
                                                   args[:exchange_segment] =
                                                     instrument_result[:result][:exchange_segment]
                                                   args[:security_id] = instrument_result[:result][:security_id]
                                                 end
                                               end
                                               # For indices like NIFTY, use IDX_I; for stocks, try NSE_FNO first
                                               if args[:symbol] && !args[:exchange_segment]
                                                 symbol_up = args[:symbol].to_s.upcase
                                                 args[:exchange_segment] = if %w[NIFTY BANKNIFTY FINNIFTY MIDCPNIFTY SENSEX BANKEX].include?(symbol_up)
                                                                              "IDX_I"
                                                                            else
                                                                              "NSE_FNO"
                                                                            end
                                               end

                                               normalized_security_id = args[:security_id] ? args[:security_id].to_i : nil
                                               normalized_strikes_count = (args[:strikes_count] || 5).to_i
                                               DhanHQDataTools.get_option_chain(**compact_kwargs.call(
                                                 exchange_segment: args[:exchange_segment],
                                                 symbol: args[:symbol],
                                                 security_id: normalized_security_id,
                                                 expiry: args[:expiry],
                                                 strikes_count: normalized_strikes_count
                                               ))
                                             },
                                             "get_expired_options_data" => lambda { |**args|
                                               DhanHQDataTools.get_expired_options_data(**compact_kwargs.call(
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
                                             },
                                             "analyze_technical" => lambda { |**args|
                                               # Auto-detect exchange_segment if not provided but symbol is
                                               if args[:symbol] && !args[:exchange_segment] && !args[:security_id]
                                                 instrument_result = DhanHQDataTools.find_instrument(symbol: args[:symbol])
                                                 if instrument_result[:result] && !instrument_result[:error]
                                                   args[:exchange_segment] =
                                                     instrument_result[:result][:exchange_segment]
                                                   args[:security_id] = instrument_result[:result][:security_id]
                                                 end
                                               end
                                               # Default to NSE_EQ if still missing
                                               args[:exchange_segment] ||= "NSE_EQ"

                                               # Provide default dates if not specified (last 30 days for daily, last 5 days for intraday)
                                               unless args[:from_date] || args[:to_date]
                                                 today = Date.today
                                                 args[:to_date] ||= today.strftime("%Y-%m-%d")
                                                 # Use shorter period for intraday (5 days), longer for daily (30 days)
                                                 days_back = args[:interval] ? 5 : 30
                                                 args[:from_date] ||= (today - days_back).strftime("%Y-%m-%d")
                                               end

                                               normalized_security_id = args[:security_id] ? args[:security_id].to_i : nil
                                               
                                               # Fetch historical data with calculate_indicators=true
                                               historical_result = DhanHQDataTools.get_historical_data(
                                                 exchange_segment: args[:exchange_segment],
                                                 symbol: args[:symbol],
                                                 security_id: normalized_security_id,
                                                 from_date: args[:from_date],
                                                 to_date: args[:to_date],
                                                 interval: args[:interval],
                                                 expiry_code: args[:expiry_code],
                                                 calculate_indicators: true
                                               )

                                               # If indicators were calculated, return them
                                               if historical_result[:result] && historical_result[:result][:indicators]
                                                 {
                                                   action: "analyze_technical",
                                                   params: {
                                                     symbol: args[:symbol],
                                                     exchange_segment: args[:exchange_segment],
                                                     from_date: args[:from_date],
                                                     to_date: args[:to_date],
                                                     interval: args[:interval]
                                                   }.compact,
                                                   result: {
                                                     symbol: args[:symbol],
                                                     exchange_segment: args[:exchange_segment],
                                                     analysis_period: {
                                                       from: args[:from_date],
                                                       to: args[:to_date],
                                                       interval: args[:interval] || "daily"
                                                     },
                                                     indicators: historical_result[:result][:indicators],
                                                     data_points: historical_result[:result][:data_points],
                                                     instrument_info: historical_result[:result][:instrument_info]
                                                   }
                                                 }
                                               else
                                                 # Fallback: calculate indicators manually from raw data
                                                 if historical_result[:result] && historical_result[:result][:data]
                                                   indicators = DhanHQDataTools.calculate_technical_indicators(
                                                     historical_result[:result][:data]
                                                   )
                                                   {
                                                     action: "analyze_technical",
                                                     params: {
                                                       symbol: args[:symbol],
                                                       exchange_segment: args[:exchange_segment],
                                                       from_date: args[:from_date],
                                                       to_date: args[:to_date],
                                                       interval: args[:interval]
                                                     }.compact,
                                                     result: {
                                                       symbol: args[:symbol],
                                                       exchange_segment: args[:exchange_segment],
                                                       analysis_period: {
                                                         from: args[:from_date],
                                                         to: args[:to_date],
                                                         interval: args[:interval] || "daily"
                                                       },
                                                       indicators: indicators,
                                                       data_points: historical_result[:result][:count] || 0,
                                                       instrument_info: historical_result[:result][:instrument_info]
                                                     }
                                                   }
                                                 else
                                                   {
                                                     action: "analyze_technical",
                                                     error: "Failed to fetch historical data for technical analysis",
                                                     params: {
                                                       symbol: args[:symbol],
                                                       exchange_segment: args[:exchange_segment]
                                                     }
                                                   }
                                                 end
                                               end
                                             }
                                           })

    config = Ollama::Config.new
    config.model = model
    client = Ollama::Client.new(config: config)

    schema = {
      "type" => "object",
      "required" => %w[action params confidence],
      "properties" => {
        "action" => {
          "type" => "string",
          "enum" => %w[find_instrument get_market_quote get_live_ltp get_market_depth
                       get_historical_data get_expiry_list get_option_chain
                       get_expired_options_data analyze_technical finish],
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
          "description" => "Confidence level"
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
          - get_live_ltp: Get last traded price (fastest for current price) - USE THIS for "Get LTP" requests
            Parameters: symbol (required), exchange_segment (optional - auto-detected)
          - get_market_quote: Get full market quote (OHLC, depth, volume) - USE THIS for "Get market quote" requests
            Parameters: symbol (required), exchange_segment (optional - auto-detected)
          - get_historical_data: Get historical OHLCV data (daily or intraday) - USE THIS for "Get historical data" requests
            Parameters: symbol (required), from_date (optional - defaults to 30 days ago), to_date (optional - defaults to today), exchange_segment (optional - auto-detected)
          - analyze_technical: Perform technical analysis with indicators - USE THIS for "technical analysis", "analyze", "indicators", "RSI", "MACD", "Bollinger Bands" requests
            Parameters: symbol (required), from_date (optional - defaults to 30 days for daily, 5 days for intraday), to_date (optional - defaults to today), interval (optional - "1", "5", "15", "25", "60" for intraday, omit for daily), exchange_segment (optional - auto-detected)
            Returns: Technical indicators including SMA (20, 50), EMA (12, 26), RSI (14), MACD, Bollinger Bands, ATR, price range, and volume analysis
          - get_market_depth: Get full market depth (bid/ask levels, order book)
          - find_instrument: Find instrument details by symbol (returns exchange_segment, security_id) - Only use if you need security_id for a specific API that requires it
          - get_expiry_list: Get available expiry dates for options
          - get_option_chain: Get option chain for a specific expiry
          - get_expired_options_data: Get historical expired options data
          - finish: Complete the task

          Exchange segments: NSE_EQ, NSE_FNO, NSE_CURRENCY, BSE_EQ, BSE_FNO, BSE_CURRENCY, MCX_COMM, IDX_I

          IMPORTANT: When the user asks for specific data (LTP, quote, historical data), call that action DIRECTLY with the symbol.
          You can pass symbol directly to get_live_ltp, get_market_quote, and get_historical_data - they will find the instrument and exchange_segment automatically.
          For historical data, if dates are not provided, they default to the last 30 days.
          Only use find_instrument if you explicitly need the security_id for a specific purpose.

          Common workflow:
          1. For "Get LTP" → call get_live_ltp with symbol (exchange_segment auto-detected)
          2. For "Get market quote" → call get_market_quote with symbol (exchange_segment auto-detected)
          3. For "Get historical data" → call get_historical_data with symbol (dates default to last 30 days if not provided)
          4. For "Technical analysis", "Analyze stock", "Get indicators", "RSI", "MACD" → call analyze_technical with symbol (dates default to last 30 days for daily, 5 days for intraday)
          5. For options, use get_expiry_list first, then get_option_chain with the expiry date

          Common Indian stocks: RELIANCE, TCS, INFY, HDFCBANK, ICICIBANK, SBIN
          Common indices: NIFTY, BANKNIFTY, FINNIFTY

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

  def build_test_agent(model: "llama3.1:8b")
    require "ollama_client"

    client = check_ollama
    return nil unless client

    config = Ollama::Config.new
    config.model = model
    client = Ollama::Client.new(config: config)

    tools = AgentRuntime::ToolRegistry.new({
                                             "fetch" => ->(**args) { { data: "fetched", args: args } },
                                             "execute" => ->(**args) { { result: "executed", args: args } },
                                             "analyze" => ->(**args) { { analysis: "analyzed", args: args } }
                                           })

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
          "additionalProperties" => true,
          "description" => "Parameters for the action"
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

    AgentRuntime::Agent.new(
      planner: planner,
      executor: AgentRuntime::Executor.new(tool_registry: tools),
      policy: AgentRuntime::Policy.new,
      state: AgentRuntime::State.new,
      audit_log: AgentRuntime::AuditLog.new
    )
  end

  def test_agent(agent, input)
    puts "\n" + "=" * 60
    puts "Testing: #{input}"
    puts "=" * 60

    if agent.nil?
      puts "\n❌ Agent is nil. Make sure build_test_agent succeeded."
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
end

# Methods will be included in main scope by console script
