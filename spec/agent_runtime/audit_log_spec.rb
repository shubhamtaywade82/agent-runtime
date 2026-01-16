# frozen_string_literal: true

require "spec_helper"
require "json"
require "stringio"

RSpec.describe AgentRuntime::AuditLog do
  let(:audit_log) { described_class.new }

  describe "#record" do
    it "outputs JSON to stdout" do
      expect do
        audit_log.record(
          input: "test input",
          decision: AgentRuntime::Decision.new(action: "fetch"),
          result: { data: "result" }
        )
      end.to output.to_stdout
    end

    it "includes timestamp in output" do
      output = capture_stdout do
        audit_log.record(
          input: "test",
          decision: AgentRuntime::Decision.new(action: "fetch"),
          result: {}
        )
      end
      parsed = JSON.parse(output)
      expect(parsed).to have_key("time")
      expect(parsed["time"]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/)
    end

    it "includes input in output" do
      output = capture_stdout do
        audit_log.record(
          input: "test input",
          decision: AgentRuntime::Decision.new(action: "fetch"),
          result: {}
        )
      end
      parsed = JSON.parse(output)
      expect(parsed["input"]).to eq("test input")
    end

    it "includes decision in output" do
      decision = AgentRuntime::Decision.new(action: "fetch", params: {})
      output = capture_stdout do
        audit_log.record(
          input: "test",
          decision: decision,
          result: {}
        )
      end
      parsed = JSON.parse(output)
      expect(parsed["decision"]).to be_a(Hash)
      expect(parsed["decision"]["action"]).to eq("fetch")
    end

    it "includes result in output" do
      result = { data: "test", count: 42 }
      output = capture_stdout do
        audit_log.record(
          input: "test",
          decision: AgentRuntime::Decision.new(action: "fetch"),
          result: result
        )
      end
      parsed = JSON.parse(output)
      # JSON converts symbol keys to strings
      expect(parsed["result"]["data"]).to eq("test")
      expect(parsed["result"]["count"]).to eq(42)
    end

    context "with nil decision" do
      it "handles nil decision" do
        output = capture_stdout do
          audit_log.record(
            input: "test",
            decision: nil,
            result: {}
          )
        end
        parsed = JSON.parse(output)
        expect(parsed["decision"]).to be_nil
      end
    end

    context "with hash decision" do
      it "handles hash decision directly" do
        decision_hash = { action: "fetch", params: {} }
        output = capture_stdout do
          audit_log.record(
            input: "test",
            decision: decision_hash,
            result: {}
          )
        end
        parsed = JSON.parse(output)
        # JSON converts symbol keys to strings
        expect(parsed["decision"]["action"]).to eq("fetch")
        expect(parsed["decision"]["params"]).to eq({})
      end
    end

    context "with decision that responds to to_h" do
      it "converts decision to hash" do
        decision = AgentRuntime::Decision.new(action: "fetch", params: { query: "test" })
        output = capture_stdout do
          audit_log.record(
            input: "test",
            decision: decision,
            result: {}
          )
        end
        parsed = JSON.parse(output)
        expect(parsed["decision"]).to be_a(Hash)
        expect(parsed["decision"]["action"]).to eq("fetch")
      end
    end

    context "when handling edge cases" do
      it "handles empty input" do
        output = capture_stdout do
          audit_log.record(
            input: "",
            decision: AgentRuntime::Decision.new(action: "fetch"),
            result: {}
          )
        end
        parsed = JSON.parse(output)
        expect(parsed["input"]).to eq("")
      end

      it "handles nil input" do
        output = capture_stdout do
          audit_log.record(
            input: nil,
            decision: AgentRuntime::Decision.new(action: "fetch"),
            result: {}
          )
        end
        parsed = JSON.parse(output)
        expect(parsed["input"]).to be_nil
      end

      it "handles empty result" do
        output = capture_stdout do
          audit_log.record(
            input: "test",
            decision: AgentRuntime::Decision.new(action: "fetch"),
            result: {}
          )
        end
        parsed = JSON.parse(output)
        expect(parsed["result"]).to eq({})
      end

      it "handles nil result" do
        output = capture_stdout do
          audit_log.record(
            input: "test",
            decision: AgentRuntime::Decision.new(action: "fetch"),
            result: nil
          )
        end
        parsed = JSON.parse(output)
        expect(parsed["result"]).to be_nil
      end

      it "handles complex nested result" do
        result = {
          data: {
            nested: {
              array: [1, 2, 3],
              value: "test"
            }
          }
        }
        output = capture_stdout do
          audit_log.record(
            input: "test",
            decision: AgentRuntime::Decision.new(action: "fetch"),
            result: result
          )
        end
        parsed = JSON.parse(output)
        # JSON converts symbol keys to strings
        expect(parsed["result"]["data"]["nested"]["array"]).to eq([1, 2, 3])
        expect(parsed["result"]["data"]["nested"]["value"]).to eq("test")
      end

      it "handles very long input" do
        long_input = "a" * 1000
        output = capture_stdout do
          audit_log.record(
            input: long_input,
            decision: AgentRuntime::Decision.new(action: "fetch"),
            result: {}
          )
        end
        parsed = JSON.parse(output)
        expect(parsed["input"].length).to eq(1000)
      end
    end
  end

  # Helper method to capture stdout
  def capture_stdout
    old_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old_stdout
  end
end
