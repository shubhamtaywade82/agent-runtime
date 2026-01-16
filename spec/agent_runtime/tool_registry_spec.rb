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
  end
end
