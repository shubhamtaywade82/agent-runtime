# frozen_string_literal: true

module AgentRuntime
  class Policy
    def validate!(decision, state:)
      raise PolicyViolation, "Missing action" unless decision.action
      raise PolicyViolation, "Low confidence" if decision.confidence && decision.confidence < 0.5
    end
  end
end
