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

* **Agent** - Simple orchestration (`step` for single decisions, `run` for loops)
* **AgentFSM** - Formal FSM-based agentic workflows (8 states, explicit transitions)
* **Planner** - LLM interface (`plan` uses `/generate`, `chat` uses `/chat`)
* **Policy** - Hard constraints, Ruby-only (non-negotiable safety)
* **ToolRegistry** - What can be executed
* **Executor** - Tool execution
* **State** - Explicit, serializable state
* **FSM** - Finite state machine for formal workflows
* **AuditLog** - Optional but critical for debugging

## Prerequisites

`agent_runtime` requires an Ollama client gem. See [PREREQUISITES.md](PREREQUISITES.md) for setup instructions and client compatibility.

## Installation

Add this line to your application's Gemfile:

```ruby
gem "agent_runtime"
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install agent_runtime
```

## Usage

### Simple Agent (Single Step)

For one-shot decisions or when you control the loop externally:

```ruby
require "agent_runtime"
require "ollama_client"

# 1. Set up tools
tools = AgentRuntime::ToolRegistry.new({
  "fetch" => ->(**args) { { data: "fetched", args: args } },
  "execute" => ->(**args) { { result: "executed", args: args } }
})

# 2. Configure planner (uses ollama-client)
client = Ollama::Client.new

schema = {
  "action" => "string",
  "params" => "object",
  "confidence" => "number"
}
planner = AgentRuntime::Planner.new(
  client: client,
  schema: schema,
  prompt_builder: ->(input:, state:) {
    "User request: #{input}\nContext: #{state.to_json}"
  }
)

# 3. Define policy
policy = AgentRuntime::Policy.new

# 4. Initialize state
state = AgentRuntime::State.new

# 5. Create agent
agent = AgentRuntime::Agent.new(
  planner: planner,
  executor: AgentRuntime::Executor.new(tool_registry: tools),
  policy: policy,
  state: state,
  audit_log: AgentRuntime::AuditLog.new
)

# 6. Run single step
begin
  result = agent.step(input: "Fetch market data for AAPL")
  puts result
rescue Ollama::RetryExhaustedError => e
  puts "Ollama server error: #{e.message}"
  puts "Make sure Ollama server is running: ollama serve"
rescue Ollama::NotFoundError => e
  puts "Model not found: #{e.message}"
rescue AgentRuntime::PolicyViolation => e
  puts "Policy violation: #{e.message}"
rescue => e
  puts "Error: #{e.class}: #{e.message}"
end
```

**Quick Test:** See `examples/console_example.rb` for a complete, copy-paste ready example.

### Agentic Workflow (Multi-Step Loop)

For adaptive workflows where the agent decides when to stop:

```ruby
# Same setup as above...

# Run agentic workflow
result = agent.run(initial_input: "Find best PDF library for Ruby")
# Agent iterates until termination condition
```

### Formal FSM Workflow

For production systems requiring formal state tracking and auditability:

```ruby
require "agent_runtime"
require "ollama_client"

# 1. Set up tools
tools = AgentRuntime::ToolRegistry.new({
  "search" => ->(query:) { { results: "Search results for: #{query}" } },
  "read" => ->(url:) { { content: "Content from: #{url}" } }
})

# 2. Configure client and planner
client = Ollama::Client.new

planner = AgentRuntime::Planner.new(
  client: client,
  schema: {
    "goal" => "string",
    "required_capabilities" => "array",
    "initial_steps" => "array"
  },
  prompt_builder: ->(input:, state:) {
    "Create a plan for: #{input}\nContext: #{state.to_json}"
  }
)

# 3. Create FSM-based agent
agent = AgentRuntime::AgentFSM.new(
  planner: planner,
  policy: AgentRuntime::Policy.new,
  executor: AgentRuntime::Executor.new(tool_registry: tools),
  state: AgentRuntime::State.new,
  tool_registry: tools,
  audit_log: AgentRuntime::AuditLog.new,
  max_iterations: 20
)

# 4. Run workflow
result = agent.run(initial_input: "Research Ruby memory management best practices")

# 5. Inspect FSM state
agent.fsm.state_name        # => :FINALIZE
agent.fsm.history           # => [transition records...]
```

See [FSM_WORKFLOWS.md](FSM_WORKFLOWS.md) for complete FSM documentation.

## How It Works

### Simple Agent Flow

1. **Planner** receives input and current state, calls LLM to generate a decision
2. **Policy** validates the decision (confidence, allowed actions)
3. **Executor** runs the appropriate tool
4. **State** is updated with the result
5. **AuditLog** records everything (if enabled)

### FSM Workflow Flow

1. **INTAKE** - Normalize input, initialize state
2. **PLAN** - Single-shot planning using `/generate`
3. **DECIDE** - Bounded decision (continue vs stop)
4. **EXECUTE** - LLM proposes actions using `/chat` (only looping state)
5. **OBSERVE** - Execute tools, inject real-world results
6. **LOOP_CHECK** - Control continuation
7. **FINALIZE** - Produce terminal output

See [AGENTIC_WORKFLOWS.md](AGENTIC_WORKFLOWS.md) for detailed workflow documentation.

## Key Principles

### Stateless Planning
The planner never mutates state. It's a pure function that takes input and state, returns a decision.

### Policy Enforcement
LLM cannot override policy. Policy failures stop execution immediately.

### Explicit State
No hidden memory. State is always visible, serializable, and testable.

### Tool Isolation
Tools are deterministic, testable, and side-effecting (intentionally).

### API Separation
- **PLAN state** uses `/generate` (single-shot, never loops)
- **EXECUTE state** uses `/chat` (may loop, may request tools)

## Examples

See the `examples/` directory for complete implementations:

* **Rails Integration** - Complete Rails app integration with domain-specific agents
* **Trading Agent** (dhanhq_agent) - Market data and trade execution
* **Patch Agent** - Code refactoring and patching

## Documentation

* [AGENTIC_WORKFLOWS.md](AGENTIC_WORKFLOWS.md) - Agentic workflow patterns and usage
* [FSM_WORKFLOWS.md](FSM_WORKFLOWS.md) - Formal FSM-based workflows
* [SCHEMA_GUIDE.md](SCHEMA_GUIDE.md) - JSON schema design guide (important for avoiding validation errors)
* [PREREQUISITES.md](PREREQUISITES.md) - Setup and configuration guide
* [examples/rails_example/](examples/rails_example/) - Rails integration guide

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
| Formal FSM         | ✅            | ❌                       |

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
