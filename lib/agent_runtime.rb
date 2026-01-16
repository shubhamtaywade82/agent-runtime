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
#
# The library provides two main agent implementations:
# - {Agent}: Simple step-by-step execution with multi-step loops
# - {AgentFSM}: Formal finite state machine implementation following the canonical agentic workflow
#
# @example Basic usage with Agent
#   planner = AgentRuntime::Planner.new(client: ollama_client, schema: schema, prompt_builder: builder)
#   policy = AgentRuntime::Policy.new
#   executor = AgentRuntime::Executor.new(tool_registry: tools)
#   state = AgentRuntime::State.new
#   agent = AgentRuntime::Agent.new(planner: planner, policy: policy, executor: executor, state: state)
#   result = agent.run(initial_input: "What is the weather?")
#
# @example Using AgentFSM for formal workflows
#   agent_fsm = AgentRuntime::AgentFSM.new(
#     planner: planner,
#     policy: policy,
#     executor: executor,
#     state: state,
#     tool_registry: tools
#   )
#   result = agent_fsm.run(initial_input: "Analyze this data")
#
# @see Agent
# @see AgentFSM
# @see Planner
# @see Policy
# @see Executor
# @see State
# @see ToolRegistry
module AgentRuntime
end
