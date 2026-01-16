# frozen_string_literal: true

module AgentRuntime
  # LLM interface for planning and execution (generate, chat, chat_raw)
  class Planner
    def initialize(client:, schema: nil, prompt_builder: nil)
      @client = client
      @schema = schema
      @prompt_builder = prompt_builder
    end

    # PLAN state: Single-shot planning using /generate
    # Returns structured plan, never loops
    def plan(input:, state:)
      raise ExecutionError, "Planner requires schema and prompt_builder for plan" unless @schema && @prompt_builder

      prompt = @prompt_builder.call(input: input, state: state)
      raw = @client.generate(prompt: prompt, schema: @schema)

      Decision.new(**raw.transform_keys(&:to_sym))
    end

    # EXECUTE state: Chat-based execution using /chat
    # Returns content by default (for simple responses)
    def chat(messages:, tools: nil, **)
      @client.chat(messages: messages, tools: tools, allow_chat: true, **)
    end

    # EXECUTE state: Chat with full response (for tool calling)
    # Returns full response including tool_calls
    def chat_raw(messages:, tools: nil, **)
      @client.chat_raw(messages: messages, tools: tools, allow_chat: true, **)
    end
  end
end
