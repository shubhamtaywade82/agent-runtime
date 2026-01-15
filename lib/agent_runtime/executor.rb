# frozen_string_literal: true

module AgentRuntime
  class Executor
    def initialize(tool_registry:)
      @tools = tool_registry
    end

    # rubocop:disable Lint/UnusedMethodArgument
    def execute(decision, state: nil)
      # rubocop:enable Lint/UnusedMethodArgument
      case decision.action
      when "finish"
        { done: true }
      else
        normalized_params = normalize_params(decision.params || {})
        @tools.call(decision.action, normalized_params)
      end
    rescue StandardError => e
      raise ExecutionError, e.message
    end

    private

    def normalize_params(params)
      return {} if params.nil?
      return params if params.empty?

      params.each_with_object({}) do |(key, value), normalized|
        symbol_key = key.is_a?(Symbol) ? key : key.to_sym
        normalized[symbol_key] = normalize_value(value)
      end
    end

    def normalize_value(value)
      case value
      when Hash
        normalize_params(value)
      when Array
        value.map { |item| normalize_value(item) }
      else
        value
      end
    end
  end
end
