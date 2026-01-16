# frozen_string_literal: true

require "spec_helper"

RSpec.describe AgentRuntime::Executor do
  let(:tool_registry) { instance_double(AgentRuntime::ToolRegistry) }
  let(:executor) { described_class.new(tool_registry: tool_registry) }

  describe "#initialize" do
    it "initializes with tool registry" do
      registry = AgentRuntime::ToolRegistry.new({})
      executor = described_class.new(tool_registry: registry)
      expect(executor).to be_a(described_class)
    end
  end

  describe "#execute" do
    context "with finish action" do
      it "returns done hash for finish action" do
        decision = AgentRuntime::Decision.new(action: "finish")
        result = executor.execute(decision, state: nil)
        expect(result).to eq({ done: true })
      end

      it "returns done hash regardless of params" do
        decision = AgentRuntime::Decision.new(
          action: "finish",
          params: { reason: "completed" }
        )
        result = executor.execute(decision, state: nil)
        expect(result).to eq({ done: true })
      end
    end

    context "with tool actions" do
      it "calls tool registry with normalized params" do
        decision = AgentRuntime::Decision.new(
          action: "search",
          params: { query: "test", limit: 10 }
        )
        allow(tool_registry).to receive(:call).and_return({ result: "found" })

        result = executor.execute(decision, state: nil)

        expect(tool_registry).to have_received(:call).with("search", { query: "test", limit: 10 })
        expect(result).to eq({ result: "found" })
      end

      it "normalizes string keys to symbols" do
        decision = AgentRuntime::Decision.new(
          action: "search",
          params: { "query" => "test", "limit" => 10 }
        )
        allow(tool_registry).to receive(:call).and_return({ result: "found" })

        executor.execute(decision, state: nil)

        expect(tool_registry).to have_received(:call).with("search", { query: "test", limit: 10 })
      end

      it "handles empty params" do
        decision = AgentRuntime::Decision.new(action: "search", params: {})
        allow(tool_registry).to receive(:call).and_return({ result: "found" })

        result = executor.execute(decision, state: nil)

        expect(tool_registry).to have_received(:call).with("search", {})
        expect(result).to eq({ result: "found" })
      end

      it "handles nil params" do
        decision = AgentRuntime::Decision.new(action: "search", params: nil)
        allow(tool_registry).to receive(:call).and_return({ result: "found" })

        result = executor.execute(decision, state: nil)

        expect(tool_registry).to have_received(:call).with("search", {})
        expect(result).to eq({ result: "found" })
      end

      it "normalizes nested hashes" do
        decision = AgentRuntime::Decision.new(
          action: "search",
          params: {
            "query" => "test",
            "options" => {
              "limit" => 10,
              "offset" => 0
            }
          }
        )
        allow(tool_registry).to receive(:call).and_return({ result: "found" })

        executor.execute(decision, state: nil)

        expect(tool_registry).to have_received(:call).with(
          "search",
          {
            query: "test",
            options: {
              limit: 10,
              offset: 0
            }
          }
        )
      end

      it "normalizes arrays with nested structures" do
        decision = AgentRuntime::Decision.new(
          action: "batch",
          params: {
            "items" => [
              { "id" => 1, "name" => "test" },
              { "id" => 2, "name" => "test2" }
            ]
          }
        )
        allow(tool_registry).to receive(:call).and_return({ result: "processed" })

        executor.execute(decision, state: nil)

        expect(tool_registry).to have_received(:call).with(
          "batch",
          {
            items: [
              { id: 1, name: "test" },
              { id: 2, name: "test2" }
            ]
          }
        )
      end
    end

    context "when handling errors" do
      it "raises ExecutionError when tool raises error" do
        decision = AgentRuntime::Decision.new(action: "search", params: {})
        allow(tool_registry).to receive(:call).and_raise(StandardError, "Tool failed")

        expect { executor.execute(decision, state: nil) }
          .to raise_error(AgentRuntime::ExecutionError, /Tool failed/)
      end

      it "raises ExecutionError when tool is not found" do
        decision = AgentRuntime::Decision.new(action: "unknown", params: {})
        allow(tool_registry).to receive(:call)
          .and_raise(AgentRuntime::ToolNotFound, "Tool not found: unknown")

        expect { executor.execute(decision, state: nil) }
          .to raise_error(AgentRuntime::ExecutionError, /Tool not found/)
      end

      it "preserves error message from underlying exception" do
        decision = AgentRuntime::Decision.new(action: "search", params: {})
        allow(tool_registry).to receive(:call)
          .and_raise(ArgumentError, "Invalid argument")

        expect { executor.execute(decision, state: nil) }
          .to raise_error(AgentRuntime::ExecutionError, /Invalid argument/)
      end
    end

    context "with state parameter" do
      it "accepts nil state" do
        decision = AgentRuntime::Decision.new(action: "finish")
        result = executor.execute(decision, state: nil)
        expect(result).to eq({ done: true })
      end

      it "accepts hash state" do
        decision = AgentRuntime::Decision.new(action: "finish")
        state = { step: 1 }
        result = executor.execute(decision, state: state)
        expect(result).to eq({ done: true })
      end

      it "accepts State object" do
        decision = AgentRuntime::Decision.new(action: "finish")
        state = AgentRuntime::State.new({ step: 1 })
        result = executor.execute(decision, state: state)
        expect(result).to eq({ done: true })
      end
    end

    context "when handling edge cases" do
      it "handles action with special characters" do
        decision = AgentRuntime::Decision.new(action: "search-v2", params: {})
        allow(tool_registry).to receive(:call).and_return({ result: "ok" })
        executor.execute(decision, state: nil)
        expect(tool_registry).to have_received(:call).with("search-v2", {})
      end

      it "handles params with mixed types" do
        decision = AgentRuntime::Decision.new(
          action: "process",
          params: {
            "string" => "value",
            "number" => 42,
            "boolean" => true,
            "array" => [1, 2, 3],
            "nil" => nil
          }
        )
        allow(tool_registry).to receive(:call).and_return({ result: "ok" })

        executor.execute(decision, state: nil)

        expect(tool_registry).to have_received(:call).with(
          "process",
          {
            string: "value",
            number: 42,
            boolean: true,
            array: [1, 2, 3],
            nil: nil
          }
        )
      end

      it "handles deeply nested structures" do
        decision = AgentRuntime::Decision.new(
          action: "complex",
          params: {
            "level1" => {
              "level2" => {
                "level3" => {
                  "value" => "deep"
                }
              }
            }
          }
        )
        allow(tool_registry).to receive(:call).and_return({ result: "ok" })

        executor.execute(decision, state: nil)

        expect(tool_registry).to have_received(:call).with(
          "complex",
          {
            level1: {
              level2: {
                level3: {
                  value: "deep"
                }
              }
            }
          }
        )
      end
    end
  end
end
