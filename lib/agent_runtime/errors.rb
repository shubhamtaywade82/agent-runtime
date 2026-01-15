# frozen_string_literal: true

module AgentRuntime
  class Error < StandardError; end

  class PolicyViolation < Error; end

  class UnknownAction < Error; end

  class ToolNotFound < Error; end

  class ExecutionError < Error; end

  class MaxIterationsExceeded < ExecutionError; end
end
