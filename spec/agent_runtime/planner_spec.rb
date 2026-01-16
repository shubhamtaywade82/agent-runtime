# frozen_string_literal: true

require "spec_helper"

RSpec.describe AgentRuntime::Planner do
  let(:mock_client) { instance_double(Ollama::Client) }
  let(:schema) do
    {
      "type" => "object",
      "required" => %w[action params],
      "properties" => {
        "action" => { "type" => "string" },
        "params" => { "type" => "object", "additionalProperties" => true }
      }
    }
  end
  let(:prompt_builder) { ->(input:, state: nil) { "Prompt: #{input}" } } # rubocop:disable Lint/UnusedBlockArgument
  let(:planner) { described_class.new(client: mock_client, schema: schema, prompt_builder: prompt_builder) }

  describe "#plan" do
    it "returns a Decision from client.generate response" do
      response = { "action" => "fetch", "params" => { "symbol" => "AAPL" } }
      allow(mock_client).to receive(:generate).and_return(response)

      decision = planner.plan(input: "Fetch AAPL", state: {})

      expect(decision).to be_a(AgentRuntime::Decision)
      expect(decision.action).to eq("fetch")
      expect(decision.params).to eq({ "symbol" => "AAPL" })
    end

    it "raises error when schema is missing" do
      planner_without_schema = described_class.new(client: mock_client)
      expect { planner_without_schema.plan(input: "test", state: {}) }
        .to raise_error(AgentRuntime::ExecutionError, /schema and prompt_builder/)
    end

    it "raises error when prompt_builder is missing" do
      planner_without_builder = described_class.new(client: mock_client, schema: schema)
      expect { planner_without_builder.plan(input: "test", state: {}) }
        .to raise_error(AgentRuntime::ExecutionError, /schema and prompt_builder/)
    end
  end

  describe "#chat" do
    it "calls client.chat with messages" do
      messages = [{ role: "user", content: "Hello" }]
      allow(mock_client).to receive(:chat).and_return({ "content" => "Hi" })

      result = planner.chat(messages: messages)

      expect(mock_client).to have_received(:chat).with(
        messages: messages,
        tools: nil,
        allow_chat: true
      )
      expect(result).to eq({ "content" => "Hi" })
    end
  end

  describe "#chat_raw" do
    it "calls client.chat_raw with messages and tools" do
      messages = [{ role: "user", content: "Hello" }]
      tools = []
      response = { "message" => { "content" => "Hi", "tool_calls" => [] } }
      allow(mock_client).to receive(:chat_raw).and_return(response)

      result = planner.chat_raw(messages: messages, tools: tools)

      expect(mock_client).to have_received(:chat_raw).with(
        messages: messages,
        tools: tools,
        allow_chat: true
      )
      expect(result).to eq(response)
    end

    # NOTE: Testing keyword argument passthrough requires a real client
    # or a more flexible mock setup. This is tested in integration tests.
  end

  describe "edge cases" do
    it "handles plan with empty state" do
      response = { "action" => "fetch", "params" => {} }
      allow(mock_client).to receive(:generate).and_return(response)

      decision = planner.plan(input: "test", state: {})

      expect(decision.action).to eq("fetch")
    end

    it "handles plan with complex state" do
      response = { "action" => "fetch", "params" => {} }
      complex_state = {
        step: 5,
        nested: { deep: { value: "test" } },
        array: [1, 2, 3]
      }
      allow(mock_client).to receive(:generate).and_return(response)

      decision = planner.plan(input: "test", state: complex_state)

      expect(decision.action).to eq("fetch")
    end

    it "handles plan response with symbol keys" do
      response = { action: "fetch", params: { symbol: "AAPL" } }
      allow(mock_client).to receive(:generate).and_return(response)

      decision = planner.plan(input: "test", state: {})

      expect(decision.action).to eq("fetch")
      expect(decision.params).to eq({ symbol: "AAPL" })
    end

    it "handles plan response with mixed key types" do
      response = { "action" => "fetch", params: { "symbol" => "AAPL" } }
      allow(mock_client).to receive(:generate).and_return(response)

      decision = planner.plan(input: "test", state: {})

      expect(decision.action).to eq("fetch")
    end

    it "handles chat with empty messages array" do
      allow(mock_client).to receive(:chat).and_return({ "content" => "" })

      planner.chat(messages: [])

      expect(mock_client).to have_received(:chat).with(
        messages: [],
        tools: nil,
        allow_chat: true
      )
    end

    it "handles chat with nil tools" do
      messages = [{ role: "user", content: "Hello" }]
      allow(mock_client).to receive(:chat).and_return({ "content" => "Hi" })

      planner.chat(messages: messages, tools: nil)

      expect(mock_client).to have_received(:chat).with(
        messages: messages,
        tools: nil,
        allow_chat: true
      )
    end

    it "handles chat_raw with tool calls" do
      messages = [{ role: "user", content: "Search" }]
      tools = [{ type: "function", function: { name: "search" } }]
      response = {
        "message" => {
          "content" => "",
          "tool_calls" => [
            { "function" => { "name" => "search", "arguments" => '{"query":"test"}' } }
          ]
        }
      }
      allow(mock_client).to receive(:chat_raw).and_return(response)

      result = planner.chat_raw(messages: messages, tools: tools)

      expect(result).to eq(response)
    end

    it "handles prompt_builder that returns empty string" do
      empty_builder = ->(input:, state:) { "" } # rubocop:disable Lint/UnusedBlockArgument
      planner_empty = described_class.new(
        client: mock_client,
        schema: schema,
        prompt_builder: empty_builder
      )

      response = { "action" => "fetch" }
      allow(mock_client).to receive(:generate).and_return(response)

      decision = planner_empty.plan(input: "test", state: {})

      expect(decision.action).to eq("fetch")
    end

    it "handles prompt_builder that uses state" do
      state_aware_builder = ->(input:, state:) { "Input: #{input}, State: #{state.inspect}" }
      planner_state = described_class.new(
        client: mock_client,
        schema: schema,
        prompt_builder: state_aware_builder
      )

      response = { "action" => "fetch" }
      allow(mock_client).to receive(:generate).and_return(response)

      planner_state.plan(input: "test", state: { step: 1 })

      expect(mock_client).to have_received(:generate).with(
        prompt: "Input: test, State: {:step=>1}",
        schema: schema
      )
    end
  end
end
