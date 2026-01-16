# frozen_string_literal: true

module AgentRuntime
  # Represents a decision made by the planner.
  #
  # This struct encapsulates the output of the planning phase, containing
  # the action to take, optional parameters, and optional confidence score.
  #
  # @!attribute action
  #   @return [String, Symbol] The action to execute (e.g., "search", "finish")
  #
  # @!attribute params
  #   @return [Hash, nil] Optional parameters for the action
  #
  # @!attribute confidence
  #   @return [Float, nil] Optional confidence score (0.0 to 1.0)
  #
  # @example Create a decision
  #   decision = Decision.new(
  #     action: "search",
  #     params: { query: "weather" },
  #     confidence: 0.9
  #   )
  #
  # @example Access attributes
  #   decision.action      # => "search"
  #   decision.params      # => { query: "weather" }
  #   decision.confidence  # => 0.9
  Decision = Struct.new(
    :action,
    :params,
    :confidence,
    keyword_init: true
  )
end
