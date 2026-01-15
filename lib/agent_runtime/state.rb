# frozen_string_literal: true

module AgentRuntime
  class State
    def initialize(data = {})
      @data = data
    end

    def snapshot
      @data.dup
    end

    def apply(result)
      @data.merge!(result) if result.is_a?(Hash)
    end
  end
end
