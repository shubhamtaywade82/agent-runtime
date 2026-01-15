# frozen_string_literal: true

module AgentRuntime
  class ToolRegistry
    def initialize(tools = {})
      @tools = tools
    end

    def call(action, params)
      tool = @tools.fetch(action) { raise ToolNotFoundError, "Tool not found: #{action}" }
      tool.call(**params)
    end

    def register(name, tool)
      @tools[name] = tool
    end
  end
end
