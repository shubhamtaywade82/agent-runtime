# frozen_string_literal: true

require "spec_helper"
require "json"

# rubocop:disable RSpec/MultipleMemoizedHelpers, RSpec/DescribeClass
RSpec.describe "Multi-Model Strategy Example Usage", type: :integration do
  # This spec tests the usage pattern demonstrated in examples/multi_model_strategy.rb
  # It verifies that the multi-model strategy works correctly with different models
  # for different cognitive states.

  let(:reasoning_model) { "llama3.1:8b" }
  let(:validation_model) { "mistral:7b-instruct" }
  let(:explanation_model) { "llama3.2:3b" }

  let(:reasoning_client) { instance_double(Ollama::Client) }
  let(:validation_client) { instance_double(Ollama::Client) }
  let(:explanation_client) { instance_double(Ollama::Client) }

  let(:reasoning_schema) do
    {
      "type" => "object",
      "required" => %w[market_bias regime directional_allowance confidence],
      "properties" => {
        "market_bias" => {
          "type" => "string",
          "enum" => %w[bullish bearish neutral]
        },
        "regime" => {
          "type" => "string",
          "enum" => %w[trending ranging volatile]
        },
        "directional_allowance" => {
          "type" => "object",
          "properties" => {
            "call" => { "type" => "boolean" },
            "put" => { "type" => "boolean" }
          }
        },
        "confidence" => {
          "type" => "number",
          "minimum" => 0,
          "maximum" => 1
        }
      }
    }
  end

  let(:validation_schema) do
    {
      "type" => "object",
      "required" => %w[decision reason violations],
      "properties" => {
        "decision" => {
          "type" => "string",
          "enum" => %w[ALLOW BLOCK]
        },
        "reason" => { "type" => "string" },
        "violations" => {
          "type" => "array",
          "items" => { "type" => "string" }
        }
      }
    }
  end

  let(:reasoning_prompt_builder) do
    lambda do |input:, state:|
      <<~PROMPT
        You are a market analysis engine. Analyze the structure and infer bias.

        Market Data: #{input}
        Current State: #{state.to_json}

        TASK: Infer market_bias, regime, and directional_allowance from the data.
        Respond with JSON matching the schema.
      PROMPT
    end
  end

  let(:validation_prompt_builder) do
    lambda do |input:, state:|
      analysis = state[:analysis] || {}
      <<~PROMPT
        You are a compliance officer. Your job is YES/NO validation.

        Proposed Signal: #{input}
        Market Analysis: #{analysis.to_json}

        Rules (STRICT):
        1. If HTF bias is bearish, BLOCK all calls
        2. If HTF bias is bullish, BLOCK all puts
        3. If confidence < 0.7, BLOCK
        4. If regime is "volatile", BLOCK

        TASK: Decide ALLOW or BLOCK. List any violations.
        Respond with JSON matching the schema.
      PROMPT
    end
  end

  let(:reasoning_planner) do
    AgentRuntime::Planner.new(
      client: reasoning_client,
      schema: reasoning_schema,
      prompt_builder: reasoning_prompt_builder
    )
  end

  let(:validation_planner) do
    AgentRuntime::Planner.new(
      client: validation_client,
      schema: validation_schema,
      prompt_builder: validation_prompt_builder
    )
  end

  let(:explanation_planner) do
    AgentRuntime::Planner.new(client: explanation_client)
  end

  let(:tools) do
    AgentRuntime::ToolRegistry.new({
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
                                     "validate_signal" => lambda do |signal_type:, entry:, **_kwargs|
                                       {
                                         signal: signal_type,
                                         entry: entry,
                                         validated: true,
                                         timestamp: Time.now.utc.iso8601
                                       }
                                     end,
                                     "send_alert" => lambda do |message:, **_kwargs|
                                       { sent: true, message: message }
                                     end
                                   })
  end

  # Custom FSM class that matches the example pattern
  class TestMultiModelAgentFSM < AgentRuntime::AgentFSM
    attr_accessor :reasoning_planner, :validation_planner, :explanation_planner

    def initialize(reasoning_planner:, validation_planner:, explanation_planner:, **opts)
      @reasoning_planner = reasoning_planner
      @validation_planner = validation_planner
      @explanation_planner = explanation_planner
      super(**opts)
    end

    def handle_plan
      prompt = @reasoning_planner.instance_variable_get(:@prompt_builder).call(
        input: @messages.first[:content],
        state: @state.snapshot
      )

      client = @reasoning_planner.instance_variable_get(:@client)
      schema = @reasoning_planner.instance_variable_get(:@schema)

      analysis = client.generate(
        prompt: prompt,
        schema: schema,
        model: "llama3.1:8b"
      )
      analysis = analysis.transform_keys(&:to_sym)

      @state.apply!({ analysis: analysis })
      @fsm.transition_to(AgentRuntime::FSM::STATES[:DECIDE], reason: "Analysis complete")
    rescue StandardError => e
      @fsm.transition_to(AgentRuntime::FSM::STATES[:HALT], reason: "Plan failed: #{e.message}")
    end

    def handle_decide
      prompt = @validation_planner.instance_variable_get(:@prompt_builder).call(
        input: "Validate signal: CALL at 4100",
        state: @state.snapshot
      )

      client = @validation_planner.instance_variable_get(:@client)
      schema = @validation_planner.instance_variable_get(:@schema)

      decision = client.generate(
        prompt: prompt,
        schema: schema,
        model: "mistral:7b-instruct"
      )
      decision = decision.transform_keys(&:to_sym)

      @state.apply!({ validation: decision })

      if decision[:decision] == "ALLOW"
        @fsm.transition_to(AgentRuntime::FSM::STATES[:EXECUTE], reason: "Signal validated")
      else
        @fsm.transition_to(AgentRuntime::FSM::STATES[:HALT],
                           reason: "Signal blocked: #{decision[:reason]}")
      end
    rescue StandardError
      @fsm.transition_to(AgentRuntime::FSM::STATES[:HALT], reason: "Validation failed")
    end

    def handle_execute
      @fsm.transition_to(AgentRuntime::FSM::STATES[:FINALIZE], reason: "Demo complete")
      handle_finalize
    end

    def handle_finalize
      analysis = @state.snapshot[:analysis] || {}
      validation = @state.snapshot[:validation] || {}

      if analysis.empty? || validation.empty?
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

      summary = @explanation_planner.chat(
        messages: [{ role: "user", content: summary_prompt }],
        model: "llama3.2:3b",
        options: { temperature: 0.3 }
      )

      {
        done: true,
        analysis: analysis,
        validation: validation,
        summary: summary,
        iterations: @fsm.iteration_count,
        fsm_history: @fsm.history
      }
    rescue StandardError => e
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
      []
    end
  end

  describe "multi-model strategy pattern" do
    it "uses reasoning model for PLAN state" do
      reasoning_response = {
        "market_bias" => "bullish",
        "regime" => "trending",
        "directional_allowance" => { "call" => true, "put" => false },
        "confidence" => 0.85
      }

      allow(reasoning_client).to receive(:generate)
        .with(hash_including(model: reasoning_model))
        .and_return(reasoning_response)

      agent = TestMultiModelAgentFSM.new(
        reasoning_planner: reasoning_planner,
        validation_planner: validation_planner,
        explanation_planner: explanation_planner,
        planner: reasoning_planner,
        policy: AgentRuntime::Policy.new,
        executor: AgentRuntime::Executor.new(tool_registry: tools),
        state: AgentRuntime::State.new,
        tool_registry: tools,
        max_iterations: 10
      )

      agent.run(initial_input: "Analyze market: SPY with CALL signal at 4100")

      expect(reasoning_client).to have_received(:generate)
        .with(hash_including(model: reasoning_model))
    end

    it "uses validation model for DECIDE state" do
      reasoning_response = {
        "market_bias" => "bullish",
        "regime" => "trending",
        "directional_allowance" => { "call" => true, "put" => false },
        "confidence" => 0.85
      }

      validation_response = {
        "decision" => "ALLOW",
        "reason" => "Signal aligns with bullish bias",
        "violations" => []
      }

      allow(reasoning_client).to receive(:generate)
        .with(hash_including(model: reasoning_model))
        .and_return(reasoning_response)

      allow(validation_client).to receive(:generate)
        .with(hash_including(model: validation_model))
        .and_return(validation_response)

      agent = TestMultiModelAgentFSM.new(
        reasoning_planner: reasoning_planner,
        validation_planner: validation_planner,
        explanation_planner: explanation_planner,
        planner: reasoning_planner,
        policy: AgentRuntime::Policy.new,
        executor: AgentRuntime::Executor.new(tool_registry: tools),
        state: AgentRuntime::State.new,
        tool_registry: tools,
        max_iterations: 10
      )

      agent.run(initial_input: "Analyze market: SPY with CALL signal at 4100")

      expect(validation_client).to have_received(:generate)
        .with(hash_including(model: validation_model))
    end

    it "uses explanation model for FINALIZE state" do
      reasoning_response = {
        "market_bias" => "bullish",
        "regime" => "trending",
        "directional_allowance" => { "call" => true, "put" => false },
        "confidence" => 0.85
      }

      validation_response = {
        "decision" => "ALLOW",
        "reason" => "Signal aligns with bullish bias",
        "violations" => []
      }

      explanation_response = "Bullish market trend confirmed. CALL signal approved."

      allow(reasoning_client).to receive(:generate)
        .with(hash_including(model: reasoning_model))
        .and_return(reasoning_response)

      allow(validation_client).to receive(:generate)
        .with(hash_including(model: validation_model))
        .and_return(validation_response)

      allow(explanation_client).to receive(:chat)
        .with(hash_including(model: explanation_model))
        .and_return(explanation_response)

      agent = TestMultiModelAgentFSM.new(
        reasoning_planner: reasoning_planner,
        validation_planner: validation_planner,
        explanation_planner: explanation_planner,
        planner: reasoning_planner,
        policy: AgentRuntime::Policy.new,
        executor: AgentRuntime::Executor.new(tool_registry: tools),
        state: AgentRuntime::State.new,
        tool_registry: tools,
        max_iterations: 10
      )

      result = agent.run(initial_input: "Analyze market: SPY with CALL signal at 4100")

      expect(explanation_client).to have_received(:chat)
        .with(hash_including(model: explanation_model))

      expect(result).to be_a(Hash)
      expect(result[:done]).to be true
      expect(result[:summary]).to eq(explanation_response)
    end

    it "completes full workflow with all three models" do
      reasoning_response = {
        "market_bias" => "bullish",
        "regime" => "trending",
        "directional_allowance" => { "call" => true, "put" => false },
        "confidence" => 0.85
      }

      validation_response = {
        "decision" => "ALLOW",
        "reason" => "Signal aligns with bullish bias",
        "violations" => []
      }

      explanation_response = "Bullish market trend confirmed. CALL signal approved."

      allow(reasoning_client).to receive(:generate)
        .with(hash_including(model: reasoning_model))
        .and_return(reasoning_response)

      allow(validation_client).to receive(:generate)
        .with(hash_including(model: validation_model))
        .and_return(validation_response)

      allow(explanation_client).to receive(:chat)
        .with(hash_including(model: explanation_model))
        .and_return(explanation_response)

      agent = TestMultiModelAgentFSM.new(
        reasoning_planner: reasoning_planner,
        validation_planner: validation_planner,
        explanation_planner: explanation_planner,
        planner: reasoning_planner,
        policy: AgentRuntime::Policy.new,
        executor: AgentRuntime::Executor.new(tool_registry: tools),
        state: AgentRuntime::State.new,
        tool_registry: tools,
        max_iterations: 10
      )

      result = agent.run(initial_input: "Analyze market: SPY with CALL signal at 4100")

      expect(result).to be_a(Hash)
      expect(result[:done]).to be true
      expect(result[:analysis]).to include(market_bias: "bullish", regime: "trending")
      expect(result[:validation]).to include(decision: "ALLOW")
      expect(result[:summary]).to eq(explanation_response)
      expect(result[:fsm_history]).to be_an(Array)
    end

    it "blocks signals when validation fails" do
      reasoning_response = {
        "market_bias" => "bearish",
        "regime" => "trending",
        "directional_allowance" => { "call" => false, "put" => true },
        "confidence" => 0.85
      }

      validation_response = {
        "decision" => "BLOCK",
        "reason" => "HTF bias is bearish, blocking all calls",
        "violations" => ["HTF bias bearish conflicts with CALL signal"]
      }

      allow(reasoning_client).to receive(:generate)
        .with(hash_including(model: reasoning_model))
        .and_return(reasoning_response)

      allow(validation_client).to receive(:generate)
        .with(hash_including(model: validation_model))
        .and_return(validation_response)

      agent = TestMultiModelAgentFSM.new(
        reasoning_planner: reasoning_planner,
        validation_planner: validation_planner,
        explanation_planner: explanation_planner,
        planner: reasoning_planner,
        policy: AgentRuntime::Policy.new,
        executor: AgentRuntime::Executor.new(tool_registry: tools),
        state: AgentRuntime::State.new,
        tool_registry: tools,
        max_iterations: 10
      )

      result = agent.run(initial_input: "Analyze market: SPY with CALL signal at 4100")

      expect(agent.fsm.terminal?).to be true
      expect(agent.fsm.state_name).to eq(AgentRuntime::FSM::STATES[:HALT])
      expect(result).to be_nil
    end
  end

  describe "state-specific schema validation" do
    it "validates reasoning schema structure" do
      reasoning_response = {
        "market_bias" => "bullish",
        "regime" => "trending",
        "directional_allowance" => { "call" => true, "put" => false },
        "confidence" => 0.85
      }

      allow(reasoning_client).to receive(:generate)
        .and_return(reasoning_response)

      agent = TestMultiModelAgentFSM.new(
        reasoning_planner: reasoning_planner,
        validation_planner: validation_planner,
        explanation_planner: explanation_planner,
        planner: reasoning_planner,
        policy: AgentRuntime::Policy.new,
        executor: AgentRuntime::Executor.new(tool_registry: tools),
        state: AgentRuntime::State.new,
        tool_registry: tools,
        max_iterations: 10
      )

      agent.run(initial_input: "Analyze market: SPY")

      state_snapshot = agent.state.snapshot
      analysis = state_snapshot[:analysis]

      expect(analysis).to include(:market_bias, :regime, :directional_allowance, :confidence)
      expect(analysis[:market_bias]).to be_in(%w[bullish bearish neutral])
      expect(analysis[:confidence]).to be_between(0, 1)
    end

    it "validates validation schema structure" do
      reasoning_response = {
        "market_bias" => "bullish",
        "regime" => "trending",
        "directional_allowance" => { "call" => true, "put" => false },
        "confidence" => 0.85
      }

      validation_response = {
        "decision" => "ALLOW",
        "reason" => "Signal validated",
        "violations" => []
      }

      allow(reasoning_client).to receive(:generate).and_return(reasoning_response)
      allow(validation_client).to receive(:generate).and_return(validation_response)

      agent = TestMultiModelAgentFSM.new(
        reasoning_planner: reasoning_planner,
        validation_planner: validation_planner,
        explanation_planner: explanation_planner,
        planner: reasoning_planner,
        policy: AgentRuntime::Policy.new,
        executor: AgentRuntime::Executor.new(tool_registry: tools),
        state: AgentRuntime::State.new,
        tool_registry: tools,
        max_iterations: 10
      )

      agent.run(initial_input: "Analyze market: SPY")

      state_snapshot = agent.state.snapshot
      validation = state_snapshot[:validation]

      expect(validation).to include(:decision, :reason, :violations)
      expect(validation[:decision]).to be_in(%w[ALLOW BLOCK])
      expect(validation[:violations]).to be_an(Array)
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers, RSpec/DescribeClass
