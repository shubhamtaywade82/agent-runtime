# frozen_string_literal: true

require "spec_helper"

RSpec.describe AgentRuntime::ProgressTracker do
  describe "#initialize" do
    it "initializes with empty signals by default" do
      tracker = described_class.new
      expect(tracker.empty?).to be true
      expect(tracker.signals).to eq([])
    end

    it "initializes with provided signals" do
      tracker = described_class.new(%i[signal_a signal_b])
      expect(tracker.include?(:signal_a)).to be true
      expect(tracker.include?(:signal_b)).to be true
    end

    it "converts string signals to symbols" do
      tracker = described_class.new(%w[signal_a signal_b])
      expect(tracker.include?(:signal_a)).to be true
      expect(tracker.include?(:signal_b)).to be true
    end
  end

  describe "#mark!" do
    it "marks a signal as present" do
      tracker = described_class.new
      tracker.mark!(:tool_called)
      expect(tracker.include?(:tool_called)).to be true
    end

    it "converts string signals to symbols" do
      tracker = described_class.new
      tracker.mark!("tool_called")
      expect(tracker.include?(:tool_called)).to be true
    end

    it "allows marking multiple signals" do
      tracker = described_class.new
      tracker.mark!(:signal_a)
      tracker.mark!(:signal_b)
      expect(tracker.signals).to contain_exactly(:signal_a, :signal_b)
    end

    it "does not duplicate signals" do
      tracker = described_class.new
      tracker.mark!(:signal_a)
      tracker.mark!(:signal_a)
      expect(tracker.signals).to eq([:signal_a])
    end
  end

  describe "#include?" do
    it "returns true for present signals" do
      tracker = described_class.new([:signal_a])
      expect(tracker.include?(:signal_a)).to be true
    end

    it "returns false for absent signals" do
      tracker = described_class.new
      expect(tracker.include?(:signal_a)).to be false
    end

    it "checks multiple signals (all must be present)" do
      tracker = described_class.new(%i[signal_a signal_b])
      expect(tracker.include?(:signal_a, :signal_b)).to be true
      expect(tracker.include?(:signal_a, :signal_c)).to be false
    end

    it "converts string signals to symbols" do
      tracker = described_class.new([:signal_a])
      expect(tracker.include?("signal_a")).to be true
    end
  end

  describe "#signals" do
    it "returns array of all signals" do
      tracker = described_class.new
      tracker.mark!(:signal_a)
      tracker.mark!(:signal_b)
      expect(tracker.signals).to contain_exactly(:signal_a, :signal_b)
    end

    it "returns empty array when no signals" do
      tracker = described_class.new
      expect(tracker.signals).to eq([])
    end
  end

  describe "#empty?" do
    it "returns true when no signals" do
      tracker = described_class.new
      expect(tracker.empty?).to be true
    end

    it "returns false when signals exist" do
      tracker = described_class.new([:signal_a])
      expect(tracker.empty?).to be false
    end
  end

  describe "#clear" do
    it "removes all signals" do
      tracker = described_class.new(%i[signal_a signal_b])
      tracker.clear
      expect(tracker.empty?).to be true
      expect(tracker.signals).to eq([])
    end
  end

  describe "#snapshot" do
    it "returns a copy of current signals" do
      tracker = described_class.new(%i[signal_a signal_b])
      snapshot = tracker.snapshot
      expect(snapshot).to contain_exactly(:signal_a, :signal_b)
      expect(snapshot).not_to be(tracker.signals)
    end

    it "modifications to snapshot do not affect tracker" do
      tracker = described_class.new([:signal_a])
      snapshot = tracker.snapshot
      snapshot << :signal_b
      expect(tracker.signals).to eq([:signal_a])
    end
  end
end
