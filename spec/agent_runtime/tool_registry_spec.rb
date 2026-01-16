# frozen_string_literal: true

require "spec_helper"

RSpec.describe AgentRuntime::ToolRegistry do
  let(:tools) do
    described_class.new({
                          "fetch" => ->(**args) { { data: "fetched", args: args } },
                          "execute" => ->(**_args) { { result: "executed" } }
                        })
  end

  describe "#call" do
    it "calls the registered tool with arguments" do
      result = tools.call("fetch", symbol: "AAPL", exchange: "NASDAQ")
      expect(result[:data]).to eq("fetched")
      expect(result[:args][:symbol]).to eq("AAPL")
      expect(result[:args][:exchange]).to eq("NASDAQ")
    end

    it "calls tool with empty arguments" do
      result = tools.call("execute", {})
      expect(result[:result]).to eq("executed")
    end

    it "raises error for unknown tool" do
      expect { tools.call("unknown", {}) }
        .to raise_error(AgentRuntime::ToolNotFound, /Tool not found/)
    end

    it "raises error for nil tool name" do
      expect { tools.call(nil, {}) }
        .to raise_error(AgentRuntime::ToolNotFound, /Tool not found/)
    end

    it "raises error for symbol tool name that doesn't exist" do
      expect { tools.call(:unknown, {}) }
        .to raise_error(AgentRuntime::ToolNotFound, /Tool not found/)
    end

    it "calls tool with symbol key" do
      tools_with_symbols = described_class.new({
                                                 fetch: ->(**args) { { data: "fetched", args: args } }
                                               })
      result = tools_with_symbols.call(:fetch, symbol: "AAPL")
      expect(result[:data]).to eq("fetched")
    end

    it "calls tool with string key using symbol" do
      result = tools.call("fetch", symbol: "AAPL")
      expect(result[:data]).to eq("fetched")
    end

    it "handles tool that raises error" do
      error_tool = ->(**_args) { raise StandardError, "Tool error" }
      tools_with_error = described_class.new({ "error_tool" => error_tool })

      expect { tools_with_error.call("error_tool", {}) }
        .to raise_error(StandardError, /Tool error/)
    end

    it "handles tool that returns nil" do
      nil_tool = ->(**_args) {}
      tools_with_nil = described_class.new({ "nil_tool" => nil_tool })

      result = tools_with_nil.call("nil_tool", {})
      expect(result).to be_nil
    end

    it "handles tool that returns complex structure" do
      complex_tool = lambda do |**_args|
        {
          data: { nested: { value: "test" } },
          array: [1, 2, 3],
          count: 42
        }
      end
      tools_complex = described_class.new({ "complex" => complex_tool })

      result = tools_complex.call("complex", {})
      expect(result[:data][:nested][:value]).to eq("test")
      expect(result[:array]).to eq([1, 2, 3])
      expect(result[:count]).to eq(42)
    end

    it "handles empty tool registry" do
      empty_tools = described_class.new({})
      expect { empty_tools.call("any", {}) }
        .to raise_error(AgentRuntime::ToolNotFound)
    end

    it "handles tool with no arguments" do
      no_args_tool = -> { { result: "no args" } }
      tools_no_args = described_class.new({ "no_args" => no_args_tool })

      result = tools_no_args.call("no_args", {})
      expect(result[:result]).to eq("no args")
    end

    it "handles tool with many arguments" do
      many_args_tool = ->(a:, b:, c:, d:, e:) { { sum: a + b + c + d + e } }
      tools_many = described_class.new({ "many" => many_args_tool })

      result = tools_many.call("many", { a: 1, b: 2, c: 3, d: 4, e: 5 })
      expect(result[:sum]).to eq(15)
    end

    it "handles tool that modifies arguments" do
      modify_tool = lambda { |**args|
        args[:value] = "modified"
        args
      }
      tools_modify = described_class.new({ "modify" => modify_tool })

      params = { value: "original" }
      result = tools_modify.call("modify", params)
      # Tool receives a copy, so original params shouldn't be modified
      expect(params[:value]).to eq("original")
      expect(result[:value]).to eq("modified")
    end
  end

  describe "edge cases" do
    it "handles tool names with special characters" do
      special_tool = ->(**_args) { { result: "special" } }
      tools_special = described_class.new({ "tool-v2" => special_tool })

      result = tools_special.call("tool-v2", {})
      expect(result[:result]).to eq("special")
    end

    it "handles very large number of tools" do
      many_tools = (1..1000).each_with_object({}) do |i, h|
        h["tool#{i}"] = ->(**_args) { { id: i } }
      end
      tools_many = described_class.new(many_tools)

      result = tools_many.call("tool500", {})
      expect(result[:id]).to eq(500)
    end

    it "handles tool that takes a long time" do
      slow_tool = lambda do |**_args|
        sleep(0.01)
        { result: "slow" }
      end
      tools_slow = described_class.new({ "slow" => slow_tool })

      result = tools_slow.call("slow", {})
      expect(result[:result]).to eq("slow")
    end
  end
end
