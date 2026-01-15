# frozen_string_literal: true

module AgentRuntime
  class State
    def initialize(data = {})
      @data = data
    end

    def snapshot
      @data.dup
    end

    def apply!(result)
      return unless result.is_a?(Hash)

      @data.merge!(result)
    end
  end
end
