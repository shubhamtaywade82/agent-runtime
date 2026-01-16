# Publishing Readiness Notes

This document lists the required corrections to make `agent_runtime` ready for
publishing as a generic, domain-agnostic agentic workflow gem.

## Scope
- The gem must remain generic.
- Domain-specific integrations belong in `examples/` or separate gems.
- Public docs must match actual behavior.

## Corrections Required

### 1) Remove domain-specific code from the gem
Correction:
- Remove DhanHQ and Indian market helpers from `lib/`.
- Keep domain-specific integrations under `examples/` or extract to a separate gem.

Why:
- The README states the gem contains no domain logic or hardcoded prompts.
- Shipping these helpers in `lib/` makes the gem domain-coupled.

Files:
- `lib/console_helpers.rb`
- `lib/dhanhq_console_helpers.rb`
- `bin/console`
- `CONSOLE_TESTING.md`

### 2) Fix FSM finalization
Correction:
- Ensure `AgentFSM#run` executes `handle_finalize` or `handle_halt`.
- Do not break the loop before the terminal state handler runs.

Why:
- The current implementation exits the loop early and returns `nil` instead of
  a final result or error.

Files:
- `lib/agent_runtime/agent_fsm.rb`

### 3) Align planning contract for FSM
Correction:
- Decide on a plan object and schema for FSM planning.
- Either return a dedicated plan object, or require plan fields in
  `Decision#params` and update docs/examples accordingly.

Why:
- `Planner#plan` returns a `Decision`, but FSM expects a plan with
  `goal/required_capabilities/initial_steps`. This is incompatible.

Files:
- `lib/agent_runtime/planner.rb`
- `lib/agent_runtime/decision.rb`
- `lib/agent_runtime/agent_fsm.rb`
- `README.md`

### 4) Enable tool calls in FSM
Correction:
- Provide Ollama tool definitions to `chat_raw`.
- Implement tool conversion in `AgentFSM#build_tools_for_chat` or accept tools
  in the initializer.

Why:
- Tool calling is currently disabled, so the FSM can never enter `OBSERVE`.

Files:
- `lib/agent_runtime/agent_fsm.rb`

### 5) Fix termination result in `Agent#run`
Correction:
- Always return the last tool result when the agent terminates.

Why:
- The current loop can exit before `final_result` is set.

Files:
- `lib/agent_runtime/agent.rb`

### 6) Harden tool call argument parsing
Correction:
- Handle JSON parse failures during tool call argument extraction.
- Transition to `HALT` with a clear error on parse failure.

Why:
- A malformed tool call currently raises and bypasses FSM error handling.

Files:
- `lib/agent_runtime/agent_fsm.rb`

### 7) Guard audit logging for nil decisions
Correction:
- Make `AuditLog#record` resilient to `decision` being nil.

Why:
- Plan failures in FSM can pass nil decisions and cause logging to crash.

Files:
- `lib/agent_runtime/audit_log.rb`

### 8) Make docs match behavior
Correction:
- Remove or add missing examples referenced by docs.
- Fix claims about deep merge in `State#apply!`.

Why:
- Docs currently describe examples and behaviors that do not exist.

Files:
- `README.md`
- `examples/README.md`
- `TESTING.md`
- `lib/agent_runtime/state.rb`

### 9) Remove hardcoded local paths
Correction:
- Remove absolute paths to external tooling.
- Make paths configurable or vendor example tools.

Why:
- Hardcoded paths break outside a single developer environment.

Files:
- `lib/console_helpers.rb`
- `lib/dhanhq_console_helpers.rb`
- `examples/dhanhq_example.rb`
- `CONSOLE_TESTING.md`

### 10) Publishing metadata and version bump
Correction:
- Bump gem version.
- Add a new CHANGELOG entry.
- Ensure gemspec includes `LICENSE.txt` and `CHANGELOG.md`.

Why:
- Current version is still `0.1.0` and release notes are missing.

Files:
- `lib/agent_runtime/version.rb`
- `agent-runtime.gemspec`
- `CHANGELOG.md`

## Minimal Release Checklist
- Domain-specific helpers removed from `lib/`.
- FSM run returns deterministic results.
- Plan contract documented and enforced.
- Tool calls work in FSM.
- Docs updated to reflect actual examples.
- Version bumped and changelog updated.
