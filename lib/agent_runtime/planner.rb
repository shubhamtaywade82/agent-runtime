# frozen_string_literal: true

module AgentRuntime
  # LLM interface for planning and execution.
  #
  # Provides methods for interacting with the LLM client:
  # - {#plan}: Single-shot planning using /generate endpoint
  # - {#chat}: Chat-based execution returning content
  # - {#chat_raw}: Chat-based execution returning full response with tool calls
  #
  # @example Initialize with schema and prompt builder
  #   schema = { type: "object", properties: { action: { type: "string" } } }
  #   builder = ->(input:, state:) { "Plan: #{input}" }
  #   planner = Planner.new(client: ollama_client, schema: schema, prompt_builder: builder)
  #
  # @example Planning a decision
  #   decision = planner.plan(input: "What should I do?", state: state.snapshot)
  #   # => #<AgentRuntime::Decision action="search", params={...}>
  class Planner
    # Initialize a new Planner instance.
    #
    # @param client [#generate, #chat] The LLM client (e.g., Ollama::Client)
    # @param schema [Hash, nil] Optional JSON schema for structured generation (required for #plan)
    # @param prompt_builder [Proc, nil] Optional proc to build prompts (required for #plan).
    #   Called as `prompt_builder.call(input: input, state: state)`
    # @param options [Hash] Options corresponding to API kwargs (like think:, model:) and model options
    def initialize(client:, schema: nil, prompt_builder: nil, **options)
      @client = client
      @schema = schema
      @prompt_builder = prompt_builder

      # Extract top-level known kwargs for generate and chat.
      # The rest go into 'options' hash for Ollama runtime options (e.g., temperature).
      @top_level_kwargs = {}
      @api_options = {}

      options.each do |k, v|
        if %i[model think keep_alive stream system images logprobs top_logprobs strict raw].include?(k)
          @top_level_kwargs[k] = v
        else
          @api_options[k] = v
        end
      end
    end

    # PLAN state: Single-shot planning using /generate.
    #
    # Returns a structured {Decision} object based on the LLM's response.
    # This method never loops and is used for one-shot planning decisions.
    #
    # @param input [String] The input prompt for planning
    # @param state [Hash] The current state snapshot
    # @return [Decision] A structured decision with action, params, and optional confidence
    # @raise [ExecutionError] If schema or prompt_builder are not configured
    #
    # @example
    #   decision = planner.plan(input: "What should I do next?", state: { step: 1 })
    #   # => #<AgentRuntime::Decision action="search", params={query: "..."}, confidence=0.9>
    def plan(input:, state:)
      raise ExecutionError, "Planner requires schema and prompt_builder for plan" unless @schema && @prompt_builder

      prompt = @prompt_builder.call(input: input, state: state)

      raw = @client.generate(
        prompt: prompt,
        schema: @schema,
        options: @api_options,
        **@top_level_kwargs
      )

      Decision.new(**raw.transform_keys(&:to_sym))
    end

    # EXECUTE state: Chat-based execution using /chat.
    #
    # Returns content by default (for simple responses without tool calls).
    # Use this when you only need the text response from the LLM.
    #
    # Additional keyword arguments are passed through to the client.
    #
    # @param messages [Array<Hash>] Array of message hashes with :role and :content
    # @param tools [Array<Hash>, nil] Optional array of tool definitions
    # @return [String, Hash] The chat response content
    #
    # @example
    #   messages = [{ role: "user", content: "Hello" }]
    #   response = planner.chat(messages: messages)
    #   # => "Hello! How can I help you?"
    def chat(messages:, tools: nil, **)
      response = chat_raw(messages: messages, tools: tools, **)
      # Extract string content from the response
      response.respond_to?(:content) ? response.content : response.dig("message", "content").to_s
    end

    # EXECUTE state: Chat with full response (for tool calling).
    #
    # Returns full response including tool_calls (Ollama::Response). Use this when you need
    # to extract tool calls from the LLM's response.
    #
    # Additional keyword arguments are passed through to the client.
    #
    # @param messages [Array<Hash>] Array of message hashes with :role and :content
    # @param tools [Array<Hash>, nil] Optional array of tool definitions
    # @return [Ollama::Response] Full response including message and tool_calls
    #
    # @example
    #   messages = [{ role: "user", content: "Search for weather" }]
    #   tools = [{ type: "function", function: { name: "search", ... } }]
    #   response = planner.chat_raw(messages: messages, tools: tools)
    #   # => #<Ollama::Response>
    def chat_raw(messages:, tools: nil, **kwargs)
      call_kwargs = @top_level_kwargs.merge(kwargs)

      @client.chat(
        messages: messages,
        tools: tools,
        options: @api_options,
        **call_kwargs
      )
    end
  end
end
