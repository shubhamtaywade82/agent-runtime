# frozen_string_literal: true

require "spec_helper"

RSpec.describe AgentRuntime::State do
  describe "#initialize" do
    it "initializes with empty hash by default" do
      state = described_class.new
      expect(state.snapshot).to eq({})
    end

    it "initializes with provided data" do
      initial_data = { key: "value", count: 42 }
      state = described_class.new(initial_data)
      expect(state.snapshot).to eq(initial_data)
    end

    it "initializes with nil data" do
      state = described_class.new(nil)
      # State.new(nil) will use nil as the data, which may cause issues
      # This tests the actual behavior
      expect(state.instance_variable_get(:@data)).to be_nil
    end

    it "initializes with nested hash" do
      nested_data = { user: { name: "Alice", age: 30 } }
      state = described_class.new(nested_data)
      expect(state.snapshot).to eq(nested_data)
    end
  end

  describe "#snapshot" do
    it "returns a copy of current state" do
      state = described_class.new({ key: "value" })
      snapshot = state.snapshot
      snapshot[:new_key] = "new_value"
      expect(state.snapshot[:new_key]).to be_nil
    end

    it "returns independent copies on multiple calls" do
      state = described_class.new({ count: 1 })
      snapshot1 = state.snapshot
      snapshot2 = state.snapshot
      snapshot1[:count] = 2
      expect(snapshot2[:count]).to eq(1)
    end

    it "handles empty state" do
      state = described_class.new
      expect(state.snapshot).to eq({})
    end

    it "preserves nested structures" do
      state = described_class.new({ nested: { deep: { value: 1 } } })
      snapshot = state.snapshot
      expect(snapshot[:nested][:deep][:value]).to eq(1)
    end
  end

  describe "#apply!" do
    it "merges simple hash into state" do
      state = described_class.new({ a: 1 })
      state.apply!({ b: 2 })
      expect(state.snapshot).to eq({ a: 1, b: 2 })
    end

    it "overwrites existing keys" do
      state = described_class.new({ key: "old" })
      state.apply!({ key: "new" })
      expect(state.snapshot[:key]).to eq("new")
    end

    it "deep merges nested hashes" do
      state = described_class.new({ nested: { a: 1, b: 2 } })
      state.apply!({ nested: { c: 3 } })
      expect(state.snapshot[:nested]).to eq({ a: 1, b: 2, c: 3 })
    end

    it "deep merges multiple levels" do
      state = described_class.new({ level1: { level2: { a: 1 } } })
      state.apply!({ level1: { level2: { b: 2 } } })
      expect(state.snapshot[:level1][:level2]).to eq({ a: 1, b: 2 })
    end

    it "overwrites non-hash values with hashes" do
      state = described_class.new({ key: "string" })
      state.apply!({ key: { nested: "value" } })
      expect(state.snapshot[:key]).to eq({ nested: "value" })
    end

    it "handles empty hash" do
      state = described_class.new({ key: "value" })
      state.apply!({})
      expect(state.snapshot[:key]).to eq("value")
    end

    it "ignores nil result" do
      state = described_class.new({ key: "value" })
      state.apply!(nil)
      expect(state.snapshot[:key]).to eq("value")
    end

    it "ignores non-hash result" do
      state = described_class.new({ key: "value" })
      state.apply!("not a hash")
      state.apply!(123)
      state.apply!([])
      expect(state.snapshot[:key]).to eq("value")
    end

    it "handles symbol and string keys separately" do
      state = described_class.new({ key: "value" })
      state.apply!({ "key" => "new_value" })
      # Ruby hashes treat :key and "key" as different keys
      expect(state.snapshot[:key]).to eq("value")
      expect(state.snapshot["key"]).to eq("new_value")
    end

    it "merges arrays as values (does not merge arrays themselves)" do
      state = described_class.new({ items: [1, 2] })
      state.apply!({ items: [3, 4] })
      expect(state.snapshot[:items]).to eq([3, 4])
    end

    it "handles complex nested structures" do
      state = described_class.new({
                                    user: { name: "Alice", settings: { theme: "dark" } },
                                    count: 5
                                  })
      state.apply!({
                     user: { settings: { language: "en" } },
                     count: 10
                   })
      expect(state.snapshot[:user][:name]).to eq("Alice")
      expect(state.snapshot[:user][:settings][:theme]).to eq("dark")
      expect(state.snapshot[:user][:settings][:language]).to eq("en")
      expect(state.snapshot[:count]).to eq(10)
    end

    it "handles multiple sequential applies" do
      state = described_class.new
      state.apply!({ step: 1 })
      state.apply!({ step: 2, data: "a" })
      state.apply!({ step: 3, data: "b" })
      expect(state.snapshot).to eq({ step: 3, data: "b" })
    end

    it "preserves state across multiple applies" do
      state = described_class.new({ persistent: "value" })
      state.apply!({ temp: "temp1" })
      state.apply!({ temp: "temp2" })
      expect(state.snapshot[:persistent]).to eq("value")
      expect(state.snapshot[:temp]).to eq("temp2")
    end
  end

  describe "when handling edge cases" do
    it "handles very deep nesting" do
      state = described_class.new({ a: { b: { c: { d: 1 } } } })
      state.apply!({ a: { b: { c: { e: 2 } } } })
      expect(state.snapshot[:a][:b][:c]).to eq({ d: 1, e: 2 })
    end

    it "handles boolean values" do
      state = described_class.new({ flag: true })
      state.apply!({ flag: false })
      expect(state.snapshot[:flag]).to be false
    end

    it "handles numeric values" do
      state = described_class.new({ count: 0 })
      state.apply!({ count: 100 })
      expect(state.snapshot[:count]).to eq(100)
    end

    it "handles nil values" do
      state = described_class.new({ key: "value" })
      state.apply!({ key: nil })
      expect(state.snapshot[:key]).to be_nil
    end
  end
end
