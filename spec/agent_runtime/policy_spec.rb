# frozen_string_literal: true

require "spec_helper"

RSpec.describe AgentRuntime::Policy do
  let(:policy) { described_class.new }

  describe "#validate!" do
    context "with valid decisions" do
      it "passes validation for decision with action" do
        decision = AgentRuntime::Decision.new(action: "fetch", params: {})
        expect { policy.validate!(decision, state: nil) }.not_to raise_error
      end

      it "passes validation for decision with action and params" do
        decision = AgentRuntime::Decision.new(
          action: "search",
          params: { query: "test" }
        )
        expect { policy.validate!(decision, state: nil) }.not_to raise_error
      end

      it "passes validation for decision with high confidence" do
        decision = AgentRuntime::Decision.new(
          action: "fetch",
          confidence: 0.9
        )
        expect { policy.validate!(decision, state: nil) }.not_to raise_error
      end

      it "passes validation for decision with confidence exactly 0.5" do
        decision = AgentRuntime::Decision.new(
          action: "fetch",
          confidence: 0.5
        )
        expect { policy.validate!(decision, state: nil) }.not_to raise_error
      end

      it "passes validation for decision with confidence 1.0" do
        decision = AgentRuntime::Decision.new(
          action: "fetch",
          confidence: 1.0
        )
        expect { policy.validate!(decision, state: nil) }.not_to raise_error
      end
    end

    context "with invalid decisions" do
      it "raises PolicyViolation for missing action" do
        decision = AgentRuntime::Decision.new(params: {})
        expect { policy.validate!(decision, state: nil) }
          .to raise_error(AgentRuntime::PolicyViolation, /Missing action/)
      end

      it "raises PolicyViolation for nil action" do
        decision = AgentRuntime::Decision.new(action: nil, params: {})
        expect { policy.validate!(decision, state: nil) }
          .to raise_error(AgentRuntime::PolicyViolation, /Missing action/)
      end

      it "raises PolicyViolation for empty string action" do
        decision = AgentRuntime::Decision.new(action: "", params: {})
        # Empty string is truthy, so this should pass
        expect { policy.validate!(decision, state: nil) }.not_to raise_error
      end

      it "raises PolicyViolation for low confidence" do
        decision = AgentRuntime::Decision.new(
          action: "fetch",
          confidence: 0.4
        )
        expect { policy.validate!(decision, state: nil) }
          .to raise_error(AgentRuntime::PolicyViolation, /Low confidence/)
      end

      it "raises PolicyViolation for confidence exactly 0" do
        decision = AgentRuntime::Decision.new(
          action: "fetch",
          confidence: 0.0
        )
        expect { policy.validate!(decision, state: nil) }
          .to raise_error(AgentRuntime::PolicyViolation, /Low confidence/)
      end

      it "raises PolicyViolation for negative confidence" do
        decision = AgentRuntime::Decision.new(
          action: "fetch",
          confidence: -0.1
        )
        expect { policy.validate!(decision, state: nil) }
          .to raise_error(AgentRuntime::PolicyViolation, /Low confidence/)
      end

      it "raises PolicyViolation for confidence just below threshold" do
        decision = AgentRuntime::Decision.new(
          action: "fetch",
          confidence: 0.499
        )
        expect { policy.validate!(decision, state: nil) }
          .to raise_error(AgentRuntime::PolicyViolation, /Low confidence/)
      end
    end

    context "with state parameter" do
      it "accepts nil state" do
        decision = AgentRuntime::Decision.new(action: "fetch")
        expect { policy.validate!(decision, state: nil) }.not_to raise_error
      end

      it "accepts hash state" do
        decision = AgentRuntime::Decision.new(action: "fetch")
        state = { step: 1 }
        expect { policy.validate!(decision, state: state) }.not_to raise_error
      end

      it "accepts State object" do
        decision = AgentRuntime::Decision.new(action: "fetch")
        state = AgentRuntime::State.new({ step: 1 })
        expect { policy.validate!(decision, state: state) }.not_to raise_error
      end
    end

    context "when handling edge cases" do
      it "handles decision with only action" do
        decision = AgentRuntime::Decision.new(action: "finish")
        expect { policy.validate!(decision, state: nil) }.not_to raise_error
      end

      it "handles decision with action and nil params" do
        decision = AgentRuntime::Decision.new(action: "fetch", params: nil)
        expect { policy.validate!(decision, state: nil) }.not_to raise_error
      end

      it "handles decision with very high confidence" do
        decision = AgentRuntime::Decision.new(
          action: "fetch",
          confidence: 0.999
        )
        expect { policy.validate!(decision, state: nil) }.not_to raise_error
      end

      it "handles decision with confidence exactly at threshold" do
        decision = AgentRuntime::Decision.new(
          action: "fetch",
          confidence: 0.5
        )
        expect { policy.validate!(decision, state: nil) }.not_to raise_error
      end
    end
  end
end
