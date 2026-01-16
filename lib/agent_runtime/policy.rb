# frozen_string_literal: true

module AgentRuntime
  # Validates agent decisions before execution
  class Policy
    def validate!(decision, state: nil) # rubocop:disable Lint/UnusedMethodArgument
      raise PolicyViolation, "Missing action" unless decision.action
      raise PolicyViolation, "Low confidence" if decision.confidence && decision.confidence < 0.5
    end
  end
end
