# frozen_string_literal: true

module AgentRuntime
  # Generic progress tracking for agent workflows.
  #
  # Tracks opaque signals that indicate progress toward a goal.
  # The runtime does not interpret these signals; they are domain-agnostic markers.
  #
  # This class is intentionally simple and generic. Applications define what
  # signals mean and when they indicate convergence.
  #
  # @example Basic usage
  #   tracker = ProgressTracker.new
  #   tracker.mark!(:tool_called)
  #   tracker.mark!(:step_completed)
  #   tracker.include?(:tool_called)  # => true
  #
  # @example Check multiple signals
  #   tracker.include?(:signal_a, :signal_b)  # => true if both present
  class ProgressTracker
    # Initialize a new ProgressTracker instance.
    #
    # @param signals [Array<Symbol>] Initial signals to track (default: [])
    def initialize(signals = [])
      @signals = Set.new(signals.map(&:to_sym))
    end

    # Mark a signal as present.
    #
    # @param signal [Symbol, String] The signal to mark
    # @return [void]
    #
    # @example
    #   tracker.mark!(:tool_called)
    def mark!(signal)
      @signals.add(signal.to_sym)
    end

    # Check if a signal (or all signals) are present.
    #
    # @param signals [Symbol, String, Array<Symbol, String>] Signal(s) to check
    # @return [Boolean] True if signal(s) are present
    #
    # @example Single signal
    #   tracker.include?(:tool_called)  # => true
    #
    # @example Multiple signals (all must be present)
    #   tracker.include?(:signal_a, :signal_b)  # => true if both present
    def include?(*signals)
      signals.all? { |signal| @signals.include?(signal.to_sym) }
    end

    # Get all tracked signals.
    #
    # @return [Array<Symbol>] Array of all tracked signals
    #
    # @example
    #   tracker.signals  # => [:tool_called, :step_completed]
    def signals
      @signals.to_a
    end

    # Check if any signals have been tracked.
    #
    # @return [Boolean] True if any signals are present
    #
    # @example
    #   tracker.empty?  # => false if signals exist
    def empty?
      @signals.empty?
    end

    # Clear all tracked signals.
    #
    # @return [void]
    #
    # @example
    #   tracker.clear
    def clear
      @signals.clear
    end

    # Create a snapshot of current signals.
    #
    # @return [Array<Symbol>] Copy of current signals
    #
    # @example
    #   snapshot = tracker.snapshot  # => [:tool_called]
    def snapshot
      @signals.to_a.dup
    end
  end
end
