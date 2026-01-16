# frozen_string_literal: true

require "ollama_client"

require_relative "agent_runtime/version"
require_relative "agent_runtime/agent"
require_relative "agent_runtime/agent_fsm"
require_relative "agent_runtime/planner"
require_relative "agent_runtime/policy"
require_relative "agent_runtime/executor"
require_relative "agent_runtime/state"
require_relative "agent_runtime/decision"
require_relative "agent_runtime/tool_registry"
require_relative "agent_runtime/audit_log"
require_relative "agent_runtime/errors"
require_relative "agent_runtime/fsm"

# AgentRuntime provides a deterministic, policy-driven runtime for building
# tool-using LLM agents with explicit state, policy enforcement, and auditability.
module AgentRuntime
end
