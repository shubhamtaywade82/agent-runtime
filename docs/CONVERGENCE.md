# Convergence and Progress Tracking

AgentRuntime provides generic progress tracking and convergence detection to prevent infinite agent loops.

## The Problem

Without convergence detection, agents can loop indefinitely:
- Tool calls succeed forever
- Executor keeps reasoning
- Max steps are exceeded
- No real work is finalized

The runtime tracks steps, messages, and tool calls, but it does **not** track progress toward a goal. This is a design gap that applications must fill.

## The Solution

AgentRuntime introduces **generic convergence primitives**:

1. **Progress Tracking**: Opaque signal tracking in state
2. **Convergence Policy Hook**: User-defined "done" detection
3. **Runtime Enforcement**: Deterministic halting when converged

Everything is **domain-agnostic** and **generic**.

## Progress Tracking

### ProgressTracker

The `ProgressTracker` class tracks opaque signals. The runtime does not interpret these signals; they are domain-agnostic markers.

```ruby
tracker = AgentRuntime::ProgressTracker.new
tracker.mark!(:tool_called)
tracker.mark!(:step_completed)
tracker.include?(:tool_called)  # => true
tracker.include?(:signal_a, :signal_b)  # => true if both present
```

### State Integration

Every `State` instance includes a `ProgressTracker`:

```ruby
state = AgentRuntime::State.new
state.progress.mark!(:custom_signal)
state.progress.include?(:custom_signal)  # => true
```

### Automatic Signal Emission

The `Executor` automatically marks progress signals when tools are executed:

- `:tool_called` - Marked when any tool is executed
- `:step_completed` - Marked when any tool is executed

```ruby
executor = AgentRuntime::Executor.new(tool_registry: tools)
decision = AgentRuntime::Decision.new(action: "search", params: { query: "test" })

executor.execute(decision, state: state)

state.progress.include?(:tool_called)  # => true
state.progress.include?(:step_completed)  # => true
```

**Note**: The `finish` action does not emit signals (it's not a tool execution).

## Convergence Policy

### Default Behavior

By default, `Policy#converged?` always returns `false` (never converges). This is a safe default that preserves existing behavior.

```ruby
policy = AgentRuntime::Policy.new
policy.converged?(state)  # => false (never converges)
```

### Custom Convergence Logic

Applications must override `Policy#converged?` to define when work is complete:

```ruby
class ConvergentPolicy < AgentRuntime::Policy
  def converged?(state)
    # Converge when both required signals are present
    state.progress.include?(:primary_task_done, :validation_complete)
  end
end
```

### Runtime Enforcement

The runtime checks convergence after each step:

- **Agent#run**: Checks `policy.converged?(state)` after each iteration
- **AgentFSM**: Checks `policy.converged?(state)` in `LOOP_CHECK` state

When convergence is detected, the runtime halts deterministically.

```ruby
policy = ConvergentPolicy.new
agent = AgentRuntime::Agent.new(
  planner: planner,
  policy: policy,
  executor: executor,
  state: state
)

# Application marks progress signals during execution
state.progress.mark!(:primary_task_done)
state.progress.mark!(:validation_complete)

# Agent will halt on next convergence check
result = agent.run(initial_input: "Complete task")
```

## Design Principles

### Genericity

Everything is **domain-agnostic**:

- ✅ Signals are opaque symbols (`:tool_called`, `:step_completed`)
- ✅ Runtime does not interpret signal meanings
- ✅ Convergence logic is defined by applications
- ✅ No hardcoded phase names or domain concepts

### Safety

- ✅ Default policy never converges (safe default)
- ✅ Max iterations still enforced
- ✅ Explicit termination signals still work (`finish`, `done: true`)
- ✅ Convergence is additive, not replacement

### Single Responsibility

- ✅ Runtime owns loop and safety
- ✅ Applications own progress semantics
- ✅ Policy owns convergence logic
- ✅ No domain leakage into runtime

## Examples

### Simple Convergence

Converge when a tool has been called:

```ruby
class SimpleConvergentPolicy < AgentRuntime::Policy
  def converged?(state)
    state.progress.include?(:tool_called)
  end
end
```

### Multi-Signal Convergence

Converge when multiple conditions are met:

```ruby
class MultiSignalPolicy < AgentRuntime::Policy
  def converged?(state)
    state.progress.include?(:data_fetched, :analysis_complete, :report_generated)
  end
end
```

### State-Based Convergence

Converge based on state content (not just signals):

```ruby
class StateBasedPolicy < AgentRuntime::Policy
  def converged?(state)
    snapshot = state.snapshot
    # Converge when result count reaches threshold
    snapshot[:results_count].to_i >= 10
  end
end
```

### Complex Convergence

Combine signals and state:

```ruby
class ComplexPolicy < AgentRuntime::Policy
  def converged?(state)
    # Must have both signals AND state condition
    state.progress.include?(:primary_task_done) &&
      state.snapshot[:error_count].to_i == 0
  end
end
```

## What NOT to Do

❌ **Do NOT** add domain-specific logic to the runtime:
- No coding-agent-specific logic
- No phase enums tied to use cases
- No references to files, patches, syntax, trades, etc.

❌ **Do NOT** rely on LLM output for convergence:
- No parsing "final answer" text
- No interpreting tool results semantically
- No prompt-based fixes

❌ **Do NOT** hardcode convergence in tools:
- Tools should mark progress signals
- Policy should determine convergence
- Runtime should enforce it

## Backward Compatibility

All changes are **backward compatible**:

- ✅ Existing agents without convergence policy still work
- ✅ Default behavior is current behavior + max steps
- ✅ No breaking changes to existing APIs
- ✅ Convergence is opt-in via policy override

## Testing

See `spec/agent_runtime/progress_tracker_spec.rb` and `spec/agent_runtime/convergence_spec.rb` for comprehensive test coverage.

## Summary

- **Progress Tracking**: Generic signal tracking in state
- **Convergence Policy**: User-defined "done" detection via `Policy#converged?`
- **Runtime Enforcement**: Deterministic halting when converged
- **Genericity**: No domain assumptions, fully reusable
- **Safety**: Default never converges, max steps still enforced

The runtime is responsible for **knowing when work has progressed enough to stop**, not for **doing** the work.
