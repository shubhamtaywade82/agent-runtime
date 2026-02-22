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
      @tools = {}
      @schemas = {}

      tools.each do |name, config|
        is_hash = config.is_a?(Hash) && config[:callable]
        @tools[name] = is_hash ? config[:callable] : config
        @schemas[name] = is_hash ? (config[:schema] || {}) : {}
      end
    end

    # Register all tools from an MCP Client instance.
    #
    # Automatically extracts schemas and builds a dynamic callable that forwards
    # the execution to the remote MCP server.
    #
    # @param mcp_client [MCP::Client] An initialized MCP client
    # @return [Array<String>] The names of the tools registered
    def register_mcp_client(mcp_client)
      registered_names = []

      mcp_client.tools.each do |mcp_tool|
        name = mcp_tool.name.to_s
        # The callable block routes execution back through the MCP client
        callable = ->(**args) { mcp_client.call_tool(tool: mcp_tool, arguments: args) }
        schema = extract_mcp_schema(mcp_tool)

        @tools[name] = callable
        @schemas[name] = schema
        registered_names << name
      end

      registered_names
    end

    private

    # Extracts and normalizes the schema from an MCP tool
    def extract_mcp_schema(mcp_tool)
      schema = mcp_tool.respond_to?(:input_schema) ? (mcp_tool.input_schema || {}) : {}

      # Inject description if present and schema lacks it
      if mcp_tool.respond_to?(:description) && mcp_tool.description && !schema.key?("description")
        schema["description"] = mcp_tool.description
      end

      schema
    end

    public

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

      # Symbolize keys to ensure compatibility with ** keyword expansion
      symbolized_params = params.each_with_object({}) do |(k, v), h|
        h[k.to_sym] = v
      end

      tool.call(**symbolized_params)
    end

    # Get the JSON schema for a specific tool.
    #
    # @param action [String, Symbol] The name of the tool
    # @return [Hash] The JSON schema for the tool
    def schema_for(action)
      @schemas[action] || {}
    end
  end
end
