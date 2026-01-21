# frozen_string_literal: true

module AgentRuntime
  # Validates agent decisions before execution and determines convergence.
  #
  # This class enforces policy constraints on decisions made by the planner.
  # By default, it validates that:
  # - The decision has an action
  # - The confidence (if present) is at least 0.5
  #
  # The class also provides a convergence hook that applications can override
  # to determine when the agent has completed its work. By default, convergence
  # never occurs (safe default), so agents must explicitly define convergence logic.
  #
  # @example Basic usage
  #   policy = Policy.new
  #   policy.validate!(decision, state: state)
  #
  # @example Custom policy subclass with validation
  #   class CustomPolicy < Policy
  #     def validate!(decision, state:)
  #       super
  #       raise PolicyViolation, "Action not allowed" if decision.action == "delete"
  #     end
  #   end
  #
  # @example Custom policy with convergence
  #   class ConvergentPolicy < Policy
  #     def converged?(state)
  #       state.progress.include?(:goal_achieved, :work_complete)
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

    # Check if the agent has converged (completed its work).
    #
    # This method is called by the runtime after each step to determine if
    # the agent should halt. By default, this always returns false (never converges),
    # which means agents will continue until max iterations or explicit termination.
    #
    # Applications should override this method to define domain-specific convergence
    # logic based on progress signals, state, or other criteria.
    #
    # @param state [State] The current agent state
    # @return [Boolean] True if the agent has converged and should halt
    #
    # @example Default behavior (never converges)
    #   policy = Policy.new
    #   policy.converged?(state)  # => false
    #
    # @example Custom convergence logic
    #   class ConvergentPolicy < Policy
    #     def converged?(state)
    #       # Converge when both required signals are present
    #       state.progress.include?(:primary_task_done, :validation_complete)
    #     end
    #   end
    def converged?(_state)
      false
    end
  end
end
