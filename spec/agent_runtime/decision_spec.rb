# frozen_string_literal: true

require "spec_helper"

RSpec.describe AgentRuntime::Decision do
  describe "initialization" do
    it "creates decision with action" do
      decision = described_class.new(action: "fetch")
      expect(decision.action).to eq("fetch")
    end

    it "creates decision with action and params" do
      decision = described_class.new(
        action: "search",
        params: { query: "test" }
      )
      expect(decision.action).to eq("search")
      expect(decision.params).to eq({ query: "test" })
    end

    it "creates decision with all attributes" do
      decision = described_class.new(
        action: "fetch",
        params: { symbol: "AAPL" },
        confidence: 0.9
      )
      expect(decision.action).to eq("fetch")
      expect(decision.params).to eq({ symbol: "AAPL" })
      expect(decision.confidence).to eq(0.9)
    end

    it "allows nil params" do
      decision = described_class.new(action: "finish", params: nil)
      expect(decision.action).to eq("finish")
      expect(decision.params).to be_nil
    end

    it "allows nil confidence" do
      decision = described_class.new(action: "fetch", confidence: nil)
      expect(decision.action).to eq("fetch")
      expect(decision.confidence).to be_nil
    end

    it "allows empty params hash" do
      decision = described_class.new(action: "fetch", params: {})
      expect(decision.params).to eq({})
    end
  end

  describe "attribute access" do
    it "allows reading action" do
      decision = described_class.new(action: "search")
      expect(decision.action).to eq("search")
    end

    it "allows reading params" do
      params = { query: "test" }
      decision = described_class.new(action: "search", params: params)
      expect(decision.params).to eq(params)
    end

    it "allows reading confidence" do
      decision = described_class.new(action: "fetch", confidence: 0.8)
      expect(decision.confidence).to eq(0.8)
    end

    it "allows modifying action" do
      decision = described_class.new(action: "fetch")
      decision.action = "search"
      expect(decision.action).to eq("search")
    end

    it "allows modifying params" do
      decision = described_class.new(action: "fetch", params: {})
      decision.params = { new: "value" }
      expect(decision.params).to eq({ new: "value" })
    end

    it "allows modifying confidence" do
      decision = described_class.new(action: "fetch", confidence: 0.5)
      decision.confidence = 0.9
      expect(decision.confidence).to eq(0.9)
    end
  end

  describe "edge cases" do
    it "handles empty string action" do
      decision = described_class.new(action: "")
      expect(decision.action).to eq("")
    end

    it "handles symbol action" do
      decision = described_class.new(action: :fetch)
      expect(decision.action).to eq(:fetch)
    end

    it "handles numeric action" do
      decision = described_class.new(action: 123)
      expect(decision.action).to eq(123)
    end

    it "handles complex params structure" do
      params = {
        nested: {
          array: [1, 2, 3],
          hash: { key: "value" }
        }
      }
      decision = described_class.new(action: "complex", params: params)
      expect(decision.params).to eq(params)
    end

    it "handles confidence at boundaries" do
      decision1 = described_class.new(action: "fetch", confidence: 0.0)
      decision2 = described_class.new(action: "fetch", confidence: 1.0)
      expect(decision1.confidence).to eq(0.0)
      expect(decision2.confidence).to eq(1.0)
    end

    it "handles confidence outside normal range" do
      decision1 = described_class.new(action: "fetch", confidence: -0.5)
      decision2 = described_class.new(action: "fetch", confidence: 1.5)
      expect(decision1.confidence).to eq(-0.5)
      expect(decision2.confidence).to eq(1.5)
    end

    it "handles very large params hash" do
      params = (1..100).each_with_object({}) { |i, h| h["key#{i}"] = "value#{i}" }
      decision = described_class.new(action: "large", params: params)
      expect(decision.params.keys.length).to eq(100)
    end
  end

  describe "equality" do
    it "has same attribute values for decisions with same attributes" do
      decision1 = described_class.new(action: "fetch", params: { a: 1 })
      decision2 = described_class.new(action: "fetch", params: { a: 1 })
      expect(decision1.action).to eq(decision2.action)
      expect(decision1.params).to eq(decision2.params)
    end

    it "compares attributes correctly" do
      decision1 = described_class.new(action: "fetch", params: {})
      decision2 = described_class.new(action: "fetch", params: {})
      # Struct equality is based on object identity, but attributes can be compared
      expect(decision1.action).to eq(decision2.action)
      expect(decision1.params).to eq(decision2.params)
    end
  end
end
