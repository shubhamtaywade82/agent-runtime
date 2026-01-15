# AgentRuntime

> A **deterministic, policy-driven runtime** for building safe, tool-using LLM agents.

AgentRuntime is a domain-agnostic agent runtime that provides explicit state management, policy enforcement, and tool execution for LLM-based agents. It separates reasoning (LLM) from authority (Ruby) and gates all side effects.

## Philosophy

AgentRuntime is **not another "agent framework"**. It's a reusable, deterministic runtime where:

* **LLM = reasoning only** (stateless planning)
* **Ruby = authority** (policy enforcement)
* **Side effects = gated** (tool registry)
* **State = explicit** (serializable, visible)
* **Failures = visible** (audit log, clear errors)

## Architecture

```
┌────────────────────────────┐
│  Your Application          │  ← trading, code patching, infra, CI, etc.
├────────────────────────────┤
│  Agent Runtime             │  ← planner + policy + executor + state
├────────────────────────────┤
│  ollama-client             │  ← safe LLM calls, schemas, retries
├────────────────────────────┤
│  Ollama Server             │  ← models, inference
└────────────────────────────┘
```

## Core Abstractions

The framework provides minimal but complete primitives:

* **Agent** - Orchestrates the execution loop
* **Planner** - Stateless LLM reasoning (uses `ollama-client`)
* **Policy** - Hard constraints, Ruby-only (non-negotiable safety)
* **ToolRegistry** - What can be executed
* **Executor** - Tool execution loop
* **State** - Explicit, serializable state
* **AuditLog** - Optional but critical for debugging

## Installation

Add this line to your application's Gemfile:

```ruby
gem "agent-runtime"
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install agent-runtime
```

## Usage

### Basic Example

```ruby
require "agent_runtime"
require "ollama"

# 1. Set up tools
tools = AgentRuntime::ToolRegistry.new({
  "fetch" => ->(**args) { fetch_data(args) },
  "execute" => ->(**args) { perform_action(args) }
})

# 2. Configure planner (uses ollama-client)
client = Ollama::Client.new
schema = {
  "action" => "string",
  "params" => "object",
  "confidence" => "number"
}
planner = AgentRuntime::Planner.new(client: client, schema: schema)

# 3. Define policy
policy = AgentRuntime::Policy.new(
  allowed_actions: %w[fetch execute finish],
  min_confidence: 0.7
)

# 4. Initialize state
state = AgentRuntime::State.new

# 5. Create agent
agent = AgentRuntime::Agent.new(
  planner: planner,
  executor: AgentRuntime::Executor.new(tool_registry: tools),
  policy: policy,
  state: state,
  audit: AgentRuntime::AuditLog.new
)

# 6. Run agent
result = agent.step(input: "Fetch market data for AAPL")
```

### How It Works

1. **Planner** receives input and current state, calls LLM to generate a decision
2. **Policy** validates the decision (confidence, allowed actions)
3. **Executor** runs the appropriate tool
4. **State** is updated with the result
5. **AuditLog** records everything (if enabled)

### Key Principles

#### Stateless Planning
The planner never mutates state. It's a pure function that takes input and state, returns a decision.

#### Policy Enforcement
LLM cannot override policy. Policy failures stop execution immediately.

#### Explicit State
No hidden memory. State is always visible, serializable, and testable.

#### Tool Isolation
Tools are deterministic, testable, and side-effecting (intentionally).

## Examples

See the `examples/` directory for complete implementations:

* **Trading Agent** - Market data and trade execution
* **Patch Agent** - Code refactoring and patching
* **Infra Agent** - Infrastructure automation

## What AgentRuntime Is NOT

This framework intentionally avoids:

❌ Domain logic
❌ Broker APIs
❌ Git logic
❌ HTTP clients
❌ Storage decisions
❌ Hardcoded prompts

The framework only defines **HOW agents run**, not **WHAT they do**.

## Why This Is Reusable

| Property           | AgentRuntime | Typical Agent Framework |
| ------------------ | ------------ | ----------------------- |
| Stateless planning | ✅            | ❌                       |
| Explicit state     | ✅            | ❌                       |
| Policy gate        | ✅            | ❌                       |
| Tool isolation     | ✅            | ❌                       |
| Deterministic      | ✅            | ❌                       |
| Auditable          | ✅            | ❌                       |

## Development

After checking out the repo, run:

```bash
bin/setup
```

To run tests:

```bash
rake spec
```

To run the console:

```bash
bin/console
```

## Contributing

Bug reports and pull requests are welcome. This project follows Clean Ruby principles:

* Code must be readable, straightforward, and easy to change
* Optimize for human understanding over cleverness
* Prefer simple solutions (K.I.S.S) over complex abstractions
* Methods must do one thing only
* Classes must have a single, clear responsibility

## License

The gem is available as open source under the terms of the [MIT License](LICENSE.txt).
