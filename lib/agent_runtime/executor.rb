# frozen_string_literal: true

module AgentRuntime
  class Executor
    def initialize(tool_registry:)
      @tools = tool_registry
    end

    def execute(decision, state:)
      case decision.action
      when "fetch", "execute", "analyze"
        @tools.call(decision.action, decision.params)
      when "finish"
        { done: true }
      else
        raise UnknownActionError, "Unknown action: #{decision.action}"
      end
    end
  end
end
