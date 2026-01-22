# frozen_string_literal: true

require_relative "state"

module AgentRuntime
  # Executes tool calls via ToolRegistry based on agent decisions.
  #
  # This class is responsible for executing the actions decided by the planner.
  # It normalizes parameters and delegates to the ToolRegistry for actual execution.
  #
  # @example Basic usage
  #   executor = Executor.new(tool_registry: tools)
  #   result = executor.execute(decision, state: state)
  #   # => { result: "..." }
  class Executor
    # Initialize a new Executor instance.
    #
    # @param tool_registry [ToolRegistry] The registry containing available tools
    def initialize(tool_registry:)
      @tools = tool_registry
    end

    # Execute a decision by calling the appropriate tool.
    #
    # If the action is "finish", returns a done hash without executing any tool.
    # Otherwise, normalizes parameters and calls the tool from the registry.
    #
    # When a tool is executed, this method automatically marks progress signals
    # in the state's progress tracker (if state is a State instance).
    #
    # @param decision [Decision] The decision to execute
    # @param state [State, Hash, nil] The current state (used for progress tracking if State instance)
    # @return [Hash] The execution result hash
    # @raise [ExecutionError] If execution fails or tool is not found
    #
    # @example Execute a tool call
    #   decision = Decision.new(action: "search", params: { query: "weather" })
    #   result = executor.execute(decision, state: state)
    #   # => { result: "Sunny, 72°F" }
    #   # Also marks :tool_called in state.progress
    #
    # @example Finish action
    #   decision = Decision.new(action: "finish")
    #   result = executor.execute(decision, state: state)
    #   # => { done: true }
    def execute(decision, state: nil)
      case decision.action
      when "finish"
        { done: true }
      else
        normalized_params = normalize_params(decision.params || {})
        result = @tools.call(decision.action, normalized_params)

        # Emit generic progress signal when tool is executed
        if state.is_a?(State)
          state.progress.mark!(:tool_called)
          state.progress.mark!(:step_completed)
          # Applications can mark domain-specific signals in their tools
          # Example: state.progress.mark!(:patch_applied) in a coding tool
        end

        result
      end
    rescue StandardError => e
      raise ExecutionError, e.message
    end

    private

    # Normalize parameter keys to symbols recursively.
    #
    # Converts all hash keys to symbols and recursively normalizes nested hashes and arrays.
    #
    # @param params [Hash, nil] The parameters to normalize
    # @return [Hash] Normalized hash with symbol keys
    def normalize_params(params)
      return {} if params.nil?
      return params if params.empty?

      params.each_with_object({}) do |(key, value), normalized|
        symbol_key = key.is_a?(Symbol) ? key : key.to_sym
        normalized[symbol_key] = normalize_value(value)
      end
    end

    # Normalize a value recursively (handles hashes and arrays).
    #
    # @param value [Object] The value to normalize
    # @return [Object] Normalized value (hashes normalized, arrays mapped, primitives unchanged)
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
