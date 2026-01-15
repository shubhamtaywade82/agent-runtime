# frozen_string_literal: true

module AgentRuntime
  class Policy
    def initialize(allowed_actions: %w[fetch analyze execute finish], min_confidence: 0.6)
      @allowed_actions = allowed_actions
      @min_confidence = min_confidence
    end

    def validate!(decision, state:)
      validate_confidence!(decision)
      validate_action!(decision)
    end

    private

    def validate_confidence!(decision)
      return if decision.confidence >= @min_confidence

      raise PolicyViolationError, "Low confidence: #{decision.confidence} < #{@min_confidence}"
    end

    def validate_action!(decision)
      return if @allowed_actions.include?(decision.action)

      raise PolicyViolationError, "Invalid action: #{decision.action}"
    end
  end
end
