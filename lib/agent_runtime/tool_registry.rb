# frozen_string_literal: true

module AgentRuntime
  # Registry mapping tool names to Ruby callables.
  #
  # This class maintains a registry of available tools that can be called
  # by the executor. Tools are registered as callable objects (procs, lambdas, or objects responding to #call).
  #
  # @example Initialize with tools
  #   tools = {
  #     "search" => ->(query:) { "Results for #{query}" },
  #     "calculate" => Calculator.new
  #   }
  #   registry = ToolRegistry.new(tools)
  #
  # @example Call a tool
  #   result = registry.call("search", { query: "weather" })
  #   # => "Results for weather"
  class ToolRegistry
    # Initialize a new ToolRegistry instance.
    #
    # @param tools [Hash<String, #call>] Hash mapping tool names to callable objects
    #
    # @example
    #   registry = ToolRegistry.new({
    #     "search" => ->(query:) { search_api(query) },
    #     "email" => EmailTool.new
    #   })
    def initialize(tools = {})
      @tools = tools
    end

    # Call a tool by name with the given parameters.
    #
    # @param action [String, Symbol] The name of the tool to call
    # @param params [Hash] Parameters to pass to the tool (will be keyword-argument expanded)
    # @return [Object] The result of calling the tool
    # @raise [ToolNotFound] If the tool is not registered
    #
    # @example
    #   result = registry.call("search", { query: "weather", limit: 10 })
    #   # Calls: search_tool.call(query: "weather", limit: 10)
    def call(action, params)
      tool = @tools[action]
      raise ToolNotFound, "Tool not found: #{action}" unless tool

      tool.call(**params)
    end
  end
end
