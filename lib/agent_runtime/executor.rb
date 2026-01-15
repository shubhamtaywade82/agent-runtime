# frozen_string_literal: true

module AgentRuntime
  class Executor
    def initialize(tool_registry:)
      @tools = tool_registry
    end

    def execute(decision, state:)
      case decision.action
      when "finish"
        { done: true }
      else
        @tools.call(decision.action, decision.params || {})
      end
    rescue StandardError => e
      raise ExecutionError, e.message
    end
  end
end
