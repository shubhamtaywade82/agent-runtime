# frozen_string_literal: true

require_relative "progress_tracker"

module AgentRuntime
  # Explicit, serializable state management with deep merge support.
  #
  # This class manages the agent's state throughout execution. State is stored
  # as a hash and can be snapshotted for read-only access. Updates are applied
  # using deep merge to preserve nested structures.
  #
  # The state includes a ProgressTracker for generic signal tracking. Applications
  # can mark progress signals and use them in convergence policies.
  #
  # @example Initialize with initial data
  #   state = State.new({ step: 1, context: { user: "Alice" } })
  #
  # @example Take a snapshot
  #   snapshot = state.snapshot
  #   # => { step: 1, context: { user: "Alice" } }
  #
  # @example Apply updates
  #   state.apply!({ step: 2, context: { task: "search" } })
  #   state.snapshot
  #   # => { step: 2, context: { user: "Alice", task: "search" } }
  #
  # @example Track progress
  #   state.progress.mark!(:tool_called)
  #   state.progress.include?(:tool_called)  # => true
  class State
    # Initialize a new State instance.
    #
    # @param data [Hash] Initial state data (default: {})
    def initialize(data = {})
      @data = data
      @progress = ProgressTracker.new
    end

    # Get the progress tracker for this state.
    #
    # @return [ProgressTracker] The progress tracker instance
    #
    # @example
    #   state.progress.mark!(:signal)
    attr_reader :progress

    # Create a snapshot of the current state.
    #
    # Returns a shallow copy of the state data. Modifications to the snapshot
    # will not affect the original state.
    #
    # Note: The progress tracker is not included in the snapshot. Access it
    # directly via #progress.
    #
    # @return [Hash] A copy of the current state data
    #
    # @example
    #   snapshot = state.snapshot
    #   snapshot[:new_key] = "value"  # Does not modify state
    def snapshot
      @data.dup
    end

    # Apply a result hash to the state using deep merge.
    #
    # Merges the result hash into the current state, preserving nested structures.
    # If result is not a hash, this method does nothing.
    #
    # @param result [Hash, Object] The result to merge into state (must be a Hash to apply)
    # @return [void]
    #
    # @example
    #   state = State.new({ a: 1, nested: { x: 10 } })
    #   state.apply!({ b: 2, nested: { y: 20 } })
    #   state.snapshot
    #   # => { a: 1, b: 2, nested: { x: 10, y: 20 } }
    def apply!(result)
      return unless result.is_a?(Hash)

      deep_merge!(@data, result)
    end

    private

    # Deep merge source hash into target hash.
    #
    # Recursively merges nested hashes, overwriting non-hash values.
    #
    # @param target [Hash] The target hash to merge into (modified in place)
    # @param source [Hash] The source hash to merge from
    # @return [void]
    def deep_merge!(target, source)
      source.each do |key, value|
        if target[key].is_a?(Hash) && value.is_a?(Hash)
          deep_merge!(target[key], value)
        else
          target[key] = value
        end
      end
    end
  end
end
