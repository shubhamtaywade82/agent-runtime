# Agentic Workflows in AgentRuntime

This document explains how `agent_runtime` implements agentic workflows and when to use them.

## Definition

> **An agentic workflow is a stateful control loop where a system repeatedly decides what information or actions are needed, executes them via external tools, observes the results, and adapts until a terminal condition is reached.**

## Agentic vs Non-Agentic Usage

### Non-Agentic: Single Step (`step`)

Use `step` when:

* You need a **one-shot decision**
* Steps are **known in advance**
* You control the loop **externally**
* The agent doesn't need to **adapt based on results**

```ruby
# Single decision, no loop
result = agent.step(input: "Analyze invoice #123")
# => { analysis: "...", confidence: 0.9 }
```

**Example use cases:**
- Simple Q&A
- Single tool invocation
- Classification tasks
- When you want explicit control over each step

### Agentic: Workflow Loop (`run`)

Use `run` when:

* Steps are **not known in advance**
* The agent must **adapt based on results**
* Multiple actions may be needed
* The agent decides when to **terminate**

```ruby
# Multi-step workflow until termination
result = agent.run(initial_input: "Find best PDF library for Ruby")
# Agent may: search → read docs → compare → decide → finish
# => { library: "pdf-reader", reason: "...", iterations: 4 }
```

**Example use cases:**
- Research tasks requiring multiple steps
- Complex analysis with iterative refinement
- Workflows where "enough information" is determined by the agent
- Tasks requiring tool chaining

## Implementation

### The Agentic Loop

```ruby
def run(initial_input:, input_builder: nil)
  iteration = 0
  current_input = initial_input

  loop do
    iteration += 1
    raise MaxIterationsExceeded if iteration > @max_iterations

    # 1. PLAN: LLM decides next action
    decision = @planner.plan(input: current_input, state: @state.snapshot)

    # 2. VALIDATE: Policy enforces safety
    @policy.validate!(decision, state: @state)

    # 3. EXECUTE: Tool performs action
    result = @executor.execute(decision, state: @state)

    # 4. OBSERVE: State accumulates results
    @state.apply!(result)

    # 5. AUDIT: Log everything
    @audit_log&.record(input: current_input, decision: decision, result: result)

    # 6. TERMINATE: Check if done
    break if terminated?(decision, result)

    # 7. ADAPT: Build next input from results
    current_input = input_builder ? input_builder.call(result, iteration) : build_next_input(result, iteration)
  end
end
```

### Termination Conditions

The loop terminates when:

1. **Decision action is "finish"** - Agent explicitly decides to stop
2. **Result has `done: true`** - Tool execution indicates completion
3. **Max iterations exceeded** - Safety guard prevents infinite loops

### State Accumulation

State accumulates observations across iterations:

```ruby
# Iteration 1: Search for libraries
state.snapshot
# => { search_results: [...] }

# Iteration 2: Read documentation
state.snapshot
# => { search_results: [...], docs_read: [...] }

# Iteration 3: Compare features
state.snapshot
# => { search_results: [...], docs_read: [...], comparison: {...} }
```

Each iteration sees **all previous observations** via `state.snapshot`.

## Custom Input Building

For complex workflows, provide a custom `input_builder`:

```ruby
agent.run(
  initial_input: "Find best PDF library",
  input_builder: ->(result, iteration) {
    case iteration
    when 1
      "Search RubyGems for PDF libraries"
    when 2
      "Read documentation for: #{result[:libraries].join(', ')}"
    when 3
      "Compare features: #{result[:features].inspect}"
    else
      "Summarize findings"
    end
  }
)
```

## Safety Guards

### Max Iterations

Prevents infinite loops:

```ruby
agent = AgentRuntime::Agent.new(
  # ... other components ...
  max_iterations: 20  # Default: 50
)

# Raises MaxIterationsExceeded if loop doesn't terminate
begin
  agent.run(initial_input: "...")
rescue AgentRuntime::MaxIterationsExceeded => e
  # Handle infinite loop
end
```

### Policy Enforcement

Policy validates **every decision** before execution:

```ruby
class SafePolicy < AgentRuntime::Policy
  def validate!(decision, state:)
    super

    # Prevent dangerous actions
    raise PolicyViolation if decision.action == "delete_all"

    # Require confirmation for expensive operations
    if decision.action == "expensive_operation" && state[:confirmations] < 2
      raise PolicyViolation, "Requires 2 confirmations"
    end
  end
end
```

## Example: Research Agent

```ruby
# Agent that researches topics iteratively
research_agent = AgentRuntime::Agent.new(
  planner: ResearchPlanner.new,
  policy: ResearchPolicy.new,
  executor: ResearchExecutor.new(
    tools: {
      "search" => ->(query:) { search_web(query) },
      "read" => ->(url:) { fetch_content(url) },
      "summarize" => ->(notes:) { generate_summary(notes) }
    }
  ),
  state: AgentRuntime::State.new,
  audit_log: AgentRuntime::AuditLog.new,
  max_iterations: 10
)

result = research_agent.run(
  initial_input: "Find best practices for Ruby memory management"
)

# Agent workflow:
# 1. search("Ruby memory management")
# 2. read(url: "...")
# 3. search("Ruby GC tuning")
# 4. read(url: "...")
# 5. summarize(notes: state[:notes])
# 6. finish
```

## When NOT to Use Agentic Workflows

Don't use `run` for:

❌ **Fixed pipelines** - Use `step` in a loop you control
❌ **Single-shot decisions** - Use `step` directly
❌ **Chat interfaces** - Use `step` per message
❌ **When steps are predetermined** - Use explicit control flow

## Mental Model

```
Model: decides WHAT is needed
System: decides IF it is allowed (Policy)
Tools: perform the action (Executor)
Agent loop: coordinates everything (Agent.run)
```

The agent is **the system around the LLM**, not the model itself.

## Testing Agentic Workflows

```ruby
RSpec.describe ResearchAgent do
  it "terminates after finding answer" do
    agent = ResearchAgent.build

    result = agent.run(initial_input: "What is Ruby?")

    expect(result[:done]).to be true
    expect(result[:iterations]).to be <= 10
    expect(agent.state.snapshot[:findings]).to be_present
  end

  it "respects max iterations" do
    agent = ResearchAgent.build(max_iterations: 3)

    expect {
      agent.run(initial_input: "Research infinite topic")
    }.to raise_error(AgentRuntime::MaxIterationsExceeded)
  end
end
```

## Summary

| Method | Use When                           | Agentic? |
| ------ | ---------------------------------- | -------- |
| `step` | Single decisions, external control | ❌        |
| `run`  | Multi-step, adaptive workflows     | ✅        |

Choose based on whether your workflow requires **adaptive iteration** or **explicit control**.
