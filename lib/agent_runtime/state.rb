# frozen_string_literal: true

module AgentRuntime
  # Explicit, serializable state management with deep merge support
  class State
    def initialize(data = {})
      @data = data
    end

    def snapshot
      @data.dup
    end

    def apply!(result)
      return unless result.is_a?(Hash)

      deep_merge!(@data, result)
    end

    private

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
