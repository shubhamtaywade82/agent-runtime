# Runtime Invariants Test Suite

This document describes the comprehensive test suite that verifies agent-runtime correctness through **observable invariants**, not LLM output quality.

## Philosophy

> **Agent correctness is proven by constraints, not creativity.**

These tests verify that the runtime enforces critical invariants that guarantee correctness **regardless of LLM behavior**. We do not trust LLM output; we trust observable, enforced invariants in the runtime.

## What These Tests Prove

The test suite verifies that agent-runtime is correct iff **ALL** of the following are true:

1. ✅ It cannot loop forever unless explicitly allowed
2. ✅ It cannot terminate *only because the LLM decided to*
3. ✅ It halts deterministically when convergence is reached
4. ✅ It halts deterministically when limits are exceeded
5. ✅ It remains domain-agnostic
6. ✅ It behaves identically across models (when properly mocked)

## Test Structure

The test suite is organized into 6 levels:

### Level 1: Runtime Invariants (Non-Negotiable)

These tests do **not involve Ollama at all** - they test pure runtime behavior.

#### Max-Step Enforcement

**Test:** `always halts at max steps even when executor always returns tool calls`

- Executor always returns "call a tool"
- Policy never converges
- Max steps = 5

**Expected:** Runtime stops at step 5 with explicit `MaxIterationsExceeded` error.

**Why it matters:** If this fails, the runtime is unsafe and can loop forever.

#### Convergence Halts Loop Immediately

**Test:** `stops executing when policy indicates convergence`

- Policy returns true after 2 steps
- Executor is tracked to count calls

**Expected:** Runtime halts at step 2, executor is not called again.

**Why it matters:** Proves policy controls termination, not the LLM.

#### Progress Tracking is Passive

**Test:** `does not interpret progress signals`

- Emit arbitrary signals: `:foo`, `:bar`, `:baz`
- Runtime must not crash or branch based on these

**Expected:** Runtime continues normal operation, signals remain present.

**Why it matters:** Ensures Single Responsibility Principle - runtime tracks, applications interpret.

### Level 2: Tool Safety Guarantees

#### Tool Execution Does Not Imply Success

**Test:** `continues looping when tool succeeds but policy doesn't converge`

- Tool returns `{ success: true }`
- Policy returns false

**Expected:** Runtime continues looping.

**Why it matters:** Prevents "false completion" - tools can succeed without work being done.

#### Tool Emits Progress, Not Control

**Test:** `tool emits progress but does not control termination`

- Tool is called and marks progress signals
- Policy never converges

**Expected:** Progress signals are marked, but runtime doesn't auto-terminate.

**Why it matters:** Tools inform, policy decides.

### Level 3: Policy Control Verification

#### Policy Controls Termination, Not LLM

**Test:** `terminates when policy says so, even if LLM wants to continue`

- LLM always wants to call tools
- Policy converges immediately

**Expected:** Runtime terminates immediately, no tools executed.

**Why it matters:** The LLM is never allowed to decide when the loop stops.

#### Requires Explicit Convergence Policy

**Test:** `requires explicit convergence policy - default never converges`

- Use default `Policy.new` (never converges)
- LLM wants to loop

**Expected:** Runtime hits max steps.

**Why it matters:** Convergence is not accidental - it must be explicitly defined.

### Level 4: Domain Agnosticism

#### Works Identically with Different Signal Names

**Test:** `works identically with different signal names`

- Test with coding signals: `:patch_applied`, `:syntax_ok`
- Test with trading signals: `:order_placed`, `:confirmation_received`
- Test with research signals: `:sources_collected`, `:analysis_complete`

**Expected:** Runtime behavior is identical - only signal names differ.

**Why it matters:** Runtime must not hardcode domain concepts.

#### Does Not Hardcode Domain Concepts

**Test:** `does not hardcode any domain concepts in logic`

- Checks that State doesn't have phase-specific methods
- Checks that Policy doesn't hardcode domain signals
- Checks that Executor doesn't interpret tool results

**Expected:** No domain-specific logic in runtime code.

**Why it matters:** Runtime must remain generic and reusable.

### Level 5: Deterministic Behavior

#### Produces Same Result When Run Multiple Times

**Test:** `produces same result when run multiple times with same state`

- Run agent 3 times with identical setup
- Compare iteration counts

**Expected:** All runs converge at same iteration.

**Why it matters:** Runtime behavior must be deterministic and reproducible.

### Level 6: Explicit Termination Signals

#### Terminates on 'finish' Action

**Test:** `terminates on 'finish' action regardless of policy`

- Policy never converges
- LLM returns "finish" action

**Expected:** Runtime terminates immediately.

**Why it matters:** Explicit termination signals must always work.

## Running the Tests

```bash
# Run all runtime invariants tests
bundle exec rspec spec/agent_runtime/runtime_invariants_spec.rb

# Run with documentation format
bundle exec rspec spec/agent_runtime/runtime_invariants_spec.rb --format documentation

# Run a specific test
bundle exec rspec spec/agent_runtime/runtime_invariants_spec.rb:80
```

## What Success Looks Like

When the runtime is working correctly:

- ✅ All 14 tests pass
- ✅ Tests run quickly (no LLM calls)
- ✅ Tests are deterministic (same result every time)
- ✅ Tests verify behavior, not output quality

## What These Tests Do NOT Test

These tests intentionally do NOT verify:

- ❌ "Does the output look smart?"
- ❌ "Did the model explain itself?"
- ❌ "Does it work most of the time?"
- ❌ "Does changing temperature help?"

These are distractions. We verify **constraints**, not creativity.

## The Single Most Important Invariant

> **The LLM is never allowed to decide when the loop stops.**

If stopping depends on:
- "Final answer"
- "Looks good"
- "I'm done"

Then it is broken.

## Integration with CI

These tests should be run in CI as a **gate** for correctness:

```yaml
# .github/workflows/test.yml
- name: Runtime Invariants
  run: bundle exec rspec spec/agent_runtime/runtime_invariants_spec.rb
```

If any test fails, the runtime is **not safe to use**.

## Adding New Invariant Tests

When adding new runtime features, add corresponding invariant tests:

1. Identify the invariant that must be preserved
2. Write a test that would fail if the invariant is violated
3. Ensure the test doesn't depend on LLM behavior
4. Document why the invariant matters

## Related Documentation

- [Convergence Guide](./CONVERGENCE.md) - How convergence works
- [Testing Guide](./TESTING_CONVERGENCE.md) - How to test convergence in applications
- [Architecture](./AGENTIC_WORKFLOWS.md) - Runtime architecture
