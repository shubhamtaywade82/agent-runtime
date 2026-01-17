# Formal FSM-Based Agentic Workflows

This document describes the formal finite state machine (FSM) implementation for agentic workflows in `agent_runtime`.

## FSM Definition

The agentic workflow is implemented as a formal FSM with **8 states**:

```
S0  = INTAKE      (Normalize input, initialize state)
S1  = PLAN        (Single-shot planning using /generate)
S2  = DECIDE      (Bounded decision: continue vs stop)
S3  = EXECUTE     (LLM proposes actions using /chat - ONLY looping state)
S4  = OBSERVE     (Execute tools, inject real-world results)
S5  = LOOP_CHECK  (Control continuation)
S6  = FINALIZE    (Produce terminal output)
S7  = HALT        (Error / abort)
```

## State Transitions

```
INTAKE → PLAN
PLAN → DECIDE | HALT
DECIDE → EXECUTE | FINALIZE | HALT
EXECUTE → OBSERVE | FINALIZE | HALT
OBSERVE → LOOP_CHECK
LOOP_CHECK → EXECUTE | FINALIZE | HALT
FINALIZE → (terminal)
HALT → (terminal)
```

## State-by-State Specification

### S0: INTAKE

**Purpose:** Normalize input, initialize state

**LLM:** ❌ None

**Actions:**
- Initialize message history
- Initialize state with goal
- Normalize user input

**Transition:** Always → PLAN

---

### S1: PLAN

**Purpose:** Create deterministic plan or intent

**LLM:** ✅ `/api/generate` (single-shot, never loops)

**Actions:**
- Call `planner.plan(input:, state:)`
- Produce structured plan
- Store plan in state

**Output:**
```ruby
{
  goal: "...",
  required_capabilities: [...],
  initial_steps: [...]
}
```

**Guards:**
- Output must be valid JSON
- Must satisfy schema
- Planner must have schema and prompt_builder

**Transitions:**
- `valid_plan → DECIDE`
- `invalid_plan → HALT`

---

### S2: DECIDE

**Purpose:** Make bounded decision (continue vs stop)

**LLM:** ✅ `/api/generate` OR ❌ rule-based

**Actions:**
- Evaluate plan validity
- Decide whether to continue

**Output:**
```ruby
{
  continue: true/false,
  reason: "..."
}
```

**Transitions:**
- `continue → EXECUTE`
- `stop → FINALIZE`
- `invalid → HALT`

---

### S3: EXECUTE

**Purpose:** LLM proposes next required actions

**LLM:** ✅ `/api/chat` (may loop, may request tools)

**Actions:**
- Call `planner.chat(messages:)`
- LLM may request tools
- Maintain message history

**Output:**
- Either `tool_calls[]` or final content

**Guards:**
- This is the **ONLY looping state**
- Max iterations enforced here
- No direct tool execution (tools only in OBSERVE)

**Transitions:**
- `tool_calls_present → OBSERVE`
- `no_tool_calls → FINALIZE`
- `error → HALT`

---

### S4: OBSERVE

**Purpose:** Inject real-world results

**LLM:** ❌ None

**Actions:**
- Execute requested tools via `tool_registry`
- Store tool results
- Append tool messages to history
- Update state with observations

**State Mutation:**
```ruby
{
  observations: [...],
  pending_tool_calls: nil
}
```

**Guards:**
- Tools only executed here
- All tool results stored
- Message history updated

**Transitions:**
- `always → LOOP_CHECK`

---

### S5: LOOP_CHECK

**Purpose:** Control continuation

**LLM:** ❌ None

**Actions:**
- Check max iterations
- Enforce safety constraints
- Evaluate if more actions needed

**Guards:**
- Max iterations check
- Policy validation
- Budget/time limits

**Transitions:**
- `continue → EXECUTE` (loops back)
- `stop → FINALIZE`
- `violation → HALT`

---

### S6: FINALIZE

**Purpose:** Produce terminal output

**LLM:** ✅ `/api/chat` (optional, no tool calls)

**Actions:**
- Optionally call LLM for summary
- No tools allowed
- No retries
- Return final result

**Transitions:**
- `always → END` (terminal)

---

### S7: HALT

**Purpose:** Abort safely

**LLM:** ❌ None

**Causes:**
- Invalid plan
- Tool failure
- Policy violation
- Timeout
- Max iterations exceeded

**Actions:**
- Return error
- Cleanup state
- Log failure

**Transitions:**
- `always → END` (terminal)

---

## API Mapping

| State      | Uses LLM | API                     | Method       | Loops? |
| ---------- | -------- | ----------------------- | ------------ | ------ |
| INTAKE     | ❌        | –                       | –            | ❌      |
| PLAN       | ✅        | `/api/generate`         | `generate()` | ❌      |
| DECIDE     | ✅ / ❌    | `/api/generate` or code | `generate()` | ❌      |
| EXECUTE    | ✅        | `/api/chat`             | `chat_raw()` | ✅      |
| OBSERVE    | ❌        | –                       | –            | ❌      |
| LOOP_CHECK | ❌        | –                       | –            | ❌      |
| FINALIZE   | ✅        | `/api/chat` (no tools)  | `chat()`     | ❌      |
| HALT       | ❌        | –                       | –            | ❌      |

**Key Rules:**
- Only EXECUTE state loops
- PLAN is always single-shot using `generate()`
- EXECUTE uses `chat_raw()` to get full response with `tool_calls`
- FINALIZE uses `chat()` for simple responses

---

## Usage

### Basic FSM Workflow

```ruby
require "agent_runtime"
require "ollama_client"

# Setup components
client = Ollama::Client.new

planner = AgentRuntime::Planner.new(
  client: client,
  schema: {
    "type" => "object",
    "required" => ["goal"],
    "properties" => {
      "goal" => { "type" => "string" },
      "required_capabilities" => {
        "type" => "array",
        "items" => { "type" => "string" }
      },
      "initial_steps" => {
        "type" => "array",
        "items" => { "type" => "string" }
      }
    },
    "additionalProperties" => false
  },
  prompt_builder: ->(input:, state:) {
    "Create a plan for: #{input}\nContext: #{state.to_json}"
  }
)

policy = AgentRuntime::Policy.new
executor = AgentRuntime::Executor.new(tool_registry: tools)
state = AgentRuntime::State.new

tools = AgentRuntime::ToolRegistry.new({
  "search" => ->(query:) { { results: "Search results for: #{query}" } },
  "read" => ->(url:) { { content: "Content from: #{url}" } }
})

# Create FSM-based agent
agent = AgentRuntime::AgentFSM.new(
  planner: planner,
  policy: policy,
  executor: executor,
  state: state,
  tool_registry: tools,
  audit_log: AgentRuntime::AuditLog.new,
  max_iterations: 20
)

# Run workflow
result = agent.run(initial_input: "Find best PDF library for Ruby")
```

### Workflow Execution

The FSM automatically:

1. **INTAKE** - Normalizes input, initializes state
2. **PLAN** - Creates plan using `/generate`
3. **DECIDE** - Decides to continue
4. **EXECUTE** - LLM requests tools via `/chat`
5. **OBSERVE** - Tools execute, results stored
6. **LOOP_CHECK** - Evaluates continuation
7. **EXECUTE** (loop) - Continues if needed
8. **FINALIZE** - Returns result

### Inspecting FSM State

```ruby
agent = AgentRuntime::AgentFSM.new(...)

begin
  result = agent.run(initial_input: "...")
rescue AgentRuntime::ExecutionError => e
  # Inspect FSM history
  agent.fsm.history
  # => [
  #   { from: 0, to: 1, reason: "Input normalized", iteration: 0 },
  #   { from: 1, to: 2, reason: "Plan created", iteration: 0 },
  #   ...
  # ]

  # Check final state
  agent.fsm.state_name
  # => :HALT
end
```

## Guards and Safety

### Enforced Guards

These are **enforced in code**, not prompts:

| Guard                          | Enforced Where      |
| ------------------------------ | ------------------- |
| Planner is single-shot         | `handle_plan`       |
| Planner never loops            | FSM structure       |
| Executor may loop              | `handle_execute`    |
| Tools only executed in OBSERVE | `handle_observe`    |
| No retries in EXECUTE          | FSM structure       |
| Termination is explicit        | `handle_loop_check` |
| Max iterations enforced        | `handle_execute`    |

### Policy Enforcement

Policy validates decisions at key points:

- **PLAN → DECIDE:** Plan validity
- **DECIDE → EXECUTE:** Decision safety
- **LOOP_CHECK:** Continuation safety

## Testing FSM Workflows

```ruby
RSpec.describe AgentFSM do
  it "transitions through all states correctly" do
    agent = build_agent

    result = agent.run(initial_input: "Test workflow")

    expect(agent.fsm.terminal?).to be true
    expect(agent.fsm.state_name).to eq(:FINALIZE)
    expect(result[:done]).to be true
  end

  it "halts on invalid plan" do
    agent = build_agent_with_invalid_planner

    expect {
      agent.run(initial_input: "Test")
    }.to raise_error(AgentRuntime::ExecutionError)

    expect(agent.fsm.state_name).to eq(:HALT)
  end

  it "respects max iterations" do
    agent = build_agent(max_iterations: 3)

    expect {
      agent.run(initial_input: "Infinite loop test")
    }.to raise_error(AgentRuntime::MaxIterationsExceeded)
  end
end
```

## Differences from Simple `run` Method

| Feature                | `Agent.run` | `AgentFSM.run` |
| ---------------------- | ----------- | -------------- |
| State machine          | ❌           | ✅              |
| Formal states          | ❌           | ✅              |
| State inspection       | ❌           | ✅              |
| Transition history     | ❌           | ✅              |
| PLAN vs EXECUTE        | Mixed       | Separated      |
| `/generate` vs `/chat` | Mixed       | Explicit       |
| Tool call extraction   | Manual      | Automatic      |
| Message history        | Manual      | Automatic      |

## When to Use FSM vs Simple `run`

**Use `AgentFSM` when:**
- You need formal state tracking
- You want to inspect workflow progress
- You need explicit PLAN vs EXECUTE separation
- You want transition history for debugging
- You're building production systems requiring auditability

**Use `Agent.run` when:**
- Simple workflows are sufficient
- You don't need state inspection
- You want minimal overhead
- You control the loop externally

## Summary

The FSM implementation provides:

✅ **Formal state machine** with 8 well-defined states
✅ **Explicit API mapping** (`/generate` for PLAN, `/chat` for EXECUTE)
✅ **Transition validation** (invalid transitions raise errors)
✅ **State inspection** (check current state, view history)
✅ **Safety guards** (max iterations, policy enforcement)
✅ **Termination guarantees** (explicit terminal states)

This is the **implementation-grade** definition of an agentic workflow.
