# frozen_string_literal: true

module AgentRuntime
  class ToolRegistry
    def initialize(tools = {})
      @tools = tools
    end

    def call(action, params)
      tool = @tools[action]
      raise ToolNotFound, "Tool not found: #{action}" unless tool

      tool.call(**params)
    end
  end
end
