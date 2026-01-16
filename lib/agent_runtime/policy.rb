# frozen_string_literal: true

module AgentRuntime
  # Validates agent decisions before execution.
  #
  # This class enforces policy constraints on decisions made by the planner.
  # By default, it validates that:
  # - The decision has an action
  # - The confidence (if present) is at least 0.5
  #
  # Subclass this to implement custom validation logic.
  #
  # @example Basic usage
  #   policy = Policy.new
  #   policy.validate!(decision, state: state)
  #
  # @example Custom policy subclass
  #   class CustomPolicy < Policy
  #     def validate!(decision, state:)
  #       super
  #       raise PolicyViolation, "Action not allowed" if decision.action == "delete"
  #     end
  #   end
  class Policy
    # Validate a decision against policy constraints.
    #
    # @param decision [Decision] The decision to validate
    # @param state [State, Hash, nil] The current state (unused in default implementation)
    # @return [void]
    # @raise [PolicyViolation] If the decision violates policy constraints:
    #   - Missing action
    #   - Confidence below 0.5 (if confidence is present)
    #
    # @example
    #   policy.validate!(decision, state: state)
    #   # => nil (raises PolicyViolation on failure)
    def validate!(decision, state: nil) # rubocop:disable Lint/UnusedMethodArgument
      raise PolicyViolation, "Missing action" unless decision.action
      raise PolicyViolation, "Low confidence" if decision.confidence && decision.confidence < 0.5
    end
  end
end
