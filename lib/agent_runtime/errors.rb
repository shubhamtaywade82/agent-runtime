# frozen_string_literal: true

module AgentRuntime
  # Base error class for all AgentRuntime errors.
  class Error < StandardError; end

  # Raised when a decision violates policy constraints.
  #
  # @see Policy#validate!
  class PolicyViolation < Error; end

  # Raised when an unknown or invalid action is encountered.
  class UnknownAction < Error; end

  # Raised when a requested tool is not found in the registry.
  #
  # @see ToolRegistry#call
  class ToolNotFound < Error; end

  # Base class for execution-related errors.
  class ExecutionError < Error; end

  # Raised when the agent exceeds the maximum number of iterations.
  #
  # @see Agent#run
  # @see AgentFSM#run
  class MaxIterationsExceeded < ExecutionError; end
end
