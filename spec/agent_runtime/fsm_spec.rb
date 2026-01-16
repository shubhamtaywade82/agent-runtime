# frozen_string_literal: true

require "spec_helper"

RSpec.describe AgentRuntime::FSM do
  describe "#initialize" do
    it "initializes in INTAKE state" do
      fsm = described_class.new
      expect(fsm.intake?).to be true
      expect(fsm.state).to eq(described_class::STATES[:INTAKE])
    end

    it "initializes with default max_iterations" do
      fsm = described_class.new
      expect(fsm.instance_variable_get(:@max_iterations)).to eq(50)
    end

    it "initializes with custom max_iterations" do
      fsm = described_class.new(max_iterations: 100)
      expect(fsm.instance_variable_get(:@max_iterations)).to eq(100)
    end

    it "initializes with zero iteration count" do
      fsm = described_class.new
      expect(fsm.iteration_count).to eq(0)
    end

    it "initializes with empty history" do
      fsm = described_class.new
      expect(fsm.history).to eq([])
    end
  end

  describe "state predicates" do
    let(:fsm) { described_class.new }

    it "checks intake state" do
      expect(fsm.intake?).to be true
      expect(fsm.plan?).to be false
    end

    it "checks plan state" do
      fsm.transition_to(described_class::STATES[:PLAN])
      expect(fsm.plan?).to be true
      expect(fsm.intake?).to be false
    end

    it "checks decide state" do
      fsm.transition_to(described_class::STATES[:PLAN])
      fsm.transition_to(described_class::STATES[:DECIDE])
      expect(fsm.decide?).to be true
    end

    it "checks execute state" do
      fsm.transition_to(described_class::STATES[:PLAN])
      fsm.transition_to(described_class::STATES[:DECIDE])
      fsm.transition_to(described_class::STATES[:EXECUTE])
      expect(fsm.execute?).to be true
    end

    it "checks observe state" do
      fsm.transition_to(described_class::STATES[:PLAN])
      fsm.transition_to(described_class::STATES[:DECIDE])
      fsm.transition_to(described_class::STATES[:EXECUTE])
      fsm.transition_to(described_class::STATES[:OBSERVE])
      expect(fsm.observe?).to be true
    end

    it "checks loop_check state" do
      fsm.transition_to(described_class::STATES[:PLAN])
      fsm.transition_to(described_class::STATES[:DECIDE])
      fsm.transition_to(described_class::STATES[:EXECUTE])
      fsm.transition_to(described_class::STATES[:OBSERVE])
      fsm.transition_to(described_class::STATES[:LOOP_CHECK])
      expect(fsm.loop_check?).to be true
    end

    it "checks finalize state" do
      fsm.transition_to(described_class::STATES[:PLAN])
      fsm.transition_to(described_class::STATES[:DECIDE])
      fsm.transition_to(described_class::STATES[:FINALIZE])
      expect(fsm.finalize?).to be true
    end

    it "checks halt state" do
      fsm.transition_to(described_class::STATES[:PLAN])
      fsm.transition_to(described_class::STATES[:HALT])
      expect(fsm.halt?).to be true
    end
  end

  describe "#terminal?" do
    it "returns false for non-terminal states" do
      fsm = described_class.new
      expect(fsm.terminal?).to be false

      fsm.transition_to(described_class::STATES[:PLAN])
      expect(fsm.terminal?).to be false

      fsm.transition_to(described_class::STATES[:DECIDE])
      expect(fsm.terminal?).to be false
    end

    it "returns true for FINALIZE state" do
      fsm = described_class.new
      fsm.transition_to(described_class::STATES[:PLAN])
      fsm.transition_to(described_class::STATES[:DECIDE])
      fsm.transition_to(described_class::STATES[:FINALIZE])
      expect(fsm.terminal?).to be true
    end

    it "returns true for HALT state" do
      fsm = described_class.new
      fsm.transition_to(described_class::STATES[:PLAN])
      fsm.transition_to(described_class::STATES[:HALT])
      expect(fsm.terminal?).to be true
    end
  end

  describe "#transition_to" do
    it "transitions from INTAKE to PLAN" do
      fsm = described_class.new
      fsm.transition_to(described_class::STATES[:PLAN])
      expect(fsm.plan?).to be true
    end

    it "records transition in history" do
      fsm = described_class.new
      fsm.transition_to(described_class::STATES[:PLAN], reason: "Starting")
      expect(fsm.history.length).to eq(1)
      expect(fsm.history.last[:from]).to eq(described_class::STATES[:INTAKE])
      expect(fsm.history.last[:to]).to eq(described_class::STATES[:PLAN])
      expect(fsm.history.last[:reason]).to eq("Starting")
    end

    it "records iteration in history" do
      fsm = described_class.new
      fsm.increment_iteration
      fsm.transition_to(described_class::STATES[:PLAN])
      expect(fsm.history.last[:iteration]).to eq(1)
    end

    it "allows nil reason" do
      fsm = described_class.new
      fsm.transition_to(described_class::STATES[:PLAN], reason: nil)
      expect(fsm.history.last[:reason]).to be_nil
    end

    it "raises error for invalid transition" do
      fsm = described_class.new
      expect do
        fsm.transition_to(described_class::STATES[:EXECUTE])
      end.to raise_error(AgentRuntime::ExecutionError, /Invalid transition/)
    end

    it "raises error for transition from terminal state" do
      fsm = described_class.new
      fsm.transition_to(described_class::STATES[:PLAN])
      fsm.transition_to(described_class::STATES[:DECIDE])
      fsm.transition_to(described_class::STATES[:FINALIZE])

      expect do
        fsm.transition_to(described_class::STATES[:PLAN])
      end.to raise_error(AgentRuntime::ExecutionError, /Invalid transition/)
    end
  end

  describe "#increment_iteration" do
    it "increments iteration count" do
      fsm = described_class.new
      fsm.increment_iteration
      expect(fsm.iteration_count).to eq(1)
      fsm.increment_iteration
      expect(fsm.iteration_count).to eq(2)
    end

    it "raises error when max iterations exceeded" do
      fsm = described_class.new(max_iterations: 2)
      fsm.increment_iteration
      fsm.increment_iteration
      expect { fsm.increment_iteration }
        .to raise_error(AgentRuntime::MaxIterationsExceeded, /Max iterations/)
    end

    it "allows exactly max_iterations" do
      fsm = described_class.new(max_iterations: 2)
      fsm.increment_iteration
      expect { fsm.increment_iteration }.not_to raise_error
    end

    it "handles zero max_iterations" do
      fsm = described_class.new(max_iterations: 0)
      expect { fsm.increment_iteration }
        .to raise_error(AgentRuntime::MaxIterationsExceeded)
    end
  end

  describe "#reset" do
    it "resets to INTAKE state" do
      fsm = described_class.new
      fsm.transition_to(described_class::STATES[:PLAN])
      fsm.reset
      expect(fsm.intake?).to be true
    end

    it "resets iteration count" do
      fsm = described_class.new
      fsm.increment_iteration
      fsm.increment_iteration
      fsm.reset
      expect(fsm.iteration_count).to eq(0)
    end

    it "clears history" do
      fsm = described_class.new
      fsm.transition_to(described_class::STATES[:PLAN])
      fsm.transition_to(described_class::STATES[:DECIDE])
      fsm.reset
      expect(fsm.history).to eq([])
    end
  end

  describe "#state_name" do
    it "returns state name for valid state" do
      fsm = described_class.new
      expect(fsm.state_name).to eq(:INTAKE)

      fsm.transition_to(described_class::STATES[:PLAN])
      expect(fsm.state_name).to eq(:PLAN)
    end

    it "returns UNKNOWN for invalid state" do
      fsm = described_class.new
      fsm.instance_variable_set(:@state, 999)
      expect(fsm.state_name).to eq("UNKNOWN")
    end
  end

  describe "#state_name_for" do
    it "returns state name for valid state value" do
      expect(described_class.new.state_name_for(described_class::STATES[:PLAN])).to eq(:PLAN)
    end

    it "returns UNKNOWN for invalid state value" do
      expect(described_class.new.state_name_for(999)).to eq("UNKNOWN")
    end
  end

  describe "valid transitions" do
    let(:fsm) { described_class.new }

    it "allows INTAKE -> PLAN" do
      expect { fsm.transition_to(described_class::STATES[:PLAN]) }.not_to raise_error
    end

    it "allows PLAN -> DECIDE" do
      fsm.transition_to(described_class::STATES[:PLAN])
      expect { fsm.transition_to(described_class::STATES[:DECIDE]) }.not_to raise_error
    end

    it "allows PLAN -> HALT" do
      fsm.transition_to(described_class::STATES[:PLAN])
      expect { fsm.transition_to(described_class::STATES[:HALT]) }.not_to raise_error
    end

    it "allows DECIDE -> EXECUTE" do
      fsm.transition_to(described_class::STATES[:PLAN])
      fsm.transition_to(described_class::STATES[:DECIDE])
      expect { fsm.transition_to(described_class::STATES[:EXECUTE]) }.not_to raise_error
    end

    it "allows DECIDE -> FINALIZE" do
      fsm.transition_to(described_class::STATES[:PLAN])
      fsm.transition_to(described_class::STATES[:DECIDE])
      expect { fsm.transition_to(described_class::STATES[:FINALIZE]) }.not_to raise_error
    end

    it "allows EXECUTE -> OBSERVE" do
      fsm.transition_to(described_class::STATES[:PLAN])
      fsm.transition_to(described_class::STATES[:DECIDE])
      fsm.transition_to(described_class::STATES[:EXECUTE])
      expect { fsm.transition_to(described_class::STATES[:OBSERVE]) }.not_to raise_error
    end

    it "allows OBSERVE -> LOOP_CHECK" do
      fsm.transition_to(described_class::STATES[:PLAN])
      fsm.transition_to(described_class::STATES[:DECIDE])
      fsm.transition_to(described_class::STATES[:EXECUTE])
      fsm.transition_to(described_class::STATES[:OBSERVE])
      expect { fsm.transition_to(described_class::STATES[:LOOP_CHECK]) }.not_to raise_error
    end

    it "allows LOOP_CHECK -> EXECUTE" do
      fsm.transition_to(described_class::STATES[:PLAN])
      fsm.transition_to(described_class::STATES[:DECIDE])
      fsm.transition_to(described_class::STATES[:EXECUTE])
      fsm.transition_to(described_class::STATES[:OBSERVE])
      fsm.transition_to(described_class::STATES[:LOOP_CHECK])
      expect { fsm.transition_to(described_class::STATES[:EXECUTE]) }.not_to raise_error
    end
  end

  describe "edge cases" do
    it "handles very large max_iterations" do
      fsm = described_class.new(max_iterations: 1_000_000)
      expect(fsm.instance_variable_get(:@max_iterations)).to eq(1_000_000)
    end

    it "handles many transitions" do
      fsm = described_class.new
      10.times do
        fsm.transition_to(described_class::STATES[:PLAN])
        fsm.transition_to(described_class::STATES[:DECIDE])
        fsm.transition_to(described_class::STATES[:EXECUTE])
        fsm.transition_to(described_class::STATES[:OBSERVE])
        fsm.transition_to(described_class::STATES[:LOOP_CHECK])
        fsm.reset
      end
      # Reset clears history, so after all iterations history should be empty
      expect(fsm.history.length).to eq(0)
    end

    it "handles long reason strings" do
      fsm = described_class.new
      long_reason = "a" * 1000
      fsm.transition_to(described_class::STATES[:PLAN], reason: long_reason)
      expect(fsm.history.last[:reason].length).to eq(1000)
    end
  end
end
