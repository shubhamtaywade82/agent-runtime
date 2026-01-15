# frozen_string_literal: true

module AgentRuntime
  class Error < StandardError; end

  class PolicyViolationError < Error; end

  class InvalidDecisionError < Error; end

  class UnknownActionError < Error; end

  class ToolNotFoundError < Error; end
end
