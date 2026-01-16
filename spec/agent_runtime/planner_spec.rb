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
  end
end
