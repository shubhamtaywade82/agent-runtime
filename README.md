# AgentRuntime

[![CI Status](https://github.com/shubhamtaywade82/agent-runtime/actions/workflows/main.yml/badge.svg)](https://github.com/shubhamtaywade82/agent-runtime/actions/workflows/main.yml)
[![RuboCop Status](https://img.shields.io/badge/code_style-rubocop-brightgreen.svg)](https://github.com/rubocop/rubocop)

Deterministic, policy-driven runtime for tool-using LLM agents in Ruby.

AgentRuntime is a control plane. It coordinates planning, policy validation,
tool execution, and explicit state. It does not ship domain logic.

## What this gem is
- A small runtime to coordinate LLM decisions with Ruby tool execution.
- A formal FSM workflow (`AgentFSM`) with explicit states and history.

## What this gem is not
- Not a domain toolkit (no broker APIs, HTTP clients, or storage).
- Not a prompt library.
- Not a memory system.

## Strict usage rules (non-negotiable)
- Use `/generate` only for planning/decision outputs (`Planner#plan`).
- Use `/chat` only during execution/finalization (`Planner#chat_raw`, `Planner#chat`).
- The LLM never executes tools. Tools are Ruby callables and run in `Executor`.
- Tool results are injected as `role: "tool"` messages only after execution.
- Only `EXECUTE` loops. All other states are single-shot.
- Termination happens only on explicit signals:
  `decision.action == "finish"`, `result[:done] == true`, `policy.converged?(state)`, or `MaxIterationsExceeded`.
- This gem does not add retries or streaming. Retry/streaming policy lives in
  `ollama-client`.

If you violate any rule above, you are not using this gem correctly.

## Narrative overview (kept here, kept strict)
AgentRuntime is a domain-agnostic runtime that separates reasoning from
authority:
- LLM reasoning happens via `Planner` only.
- Ruby owns policy and execution.
- Tools are gated and executed outside the LLM.
- State is explicit and inspectable.
- Failures are visible via explicit errors and optional audit logs.

Architecture (conceptual):
Your application → AgentRuntime → `ollama-client` → Ollama server

This overview is informative only. The strict rules above are the contract.

## Core components (SRP map)
- `Planner`: LLM interface (`generate`, `chat`, `chat_raw`). No tools. No side effects.
- `Policy`: validates decisions before execution.
- `Executor`: executes tools via `ToolRegistry` only.
- `ToolRegistry`: maps tool names to Ruby callables.
- `State`: explicit, serializable state.
- `Agent`: simple decision loop using `Planner#plan` and tools.
- `AgentFSM`: formal FSM with explicit states and transition history.
- `AuditLog`: optional logging of decisions and results.
- `ProgressTracker`: generic signal tracking for convergence detection.

## API mapping
| Concern | Method | LLM endpoint | Where it belongs |
| --- | --- | --- | --- |
| Planning / decisions | `Planner#plan` | `/api/generate` | PLAN |
| Execution / tool calls | `Planner#chat_raw` | `/api/chat` | EXECUTE |
| Final response (optional) | `Planner#chat` | `/api/chat` | FINALIZE |

`Executor` never calls the LLM.

## Prerequisites
`agent_runtime` depends on `ollama-client`. See `PREREQUISITES.md`.

For connecting to remote tools via the Model Context Protocol, see `docs/MCP_INTEGRATION.md`.

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

### Single-step agent (`Agent#step`)
Use this for one-shot decisions or when you control the loop externally.

```ruby
require "agent_runtime"
require "ollama_client"

tools = AgentRuntime::ToolRegistry.new({
  "fetch" => {
    callable: ->(ticker:) { { data: "fetched", ticker: ticker } },
    schema: {
      description: "Fetches market data",
      properties: { ticker: { type: "string" } },
      required: ["ticker"]
    }
  }
})

client = Ollama::Client.new

schema = {
  "type" => "object",
  "required" => ["action", "params", "confidence"],
  "properties" => {
    "action" => { "type" => "string", "enum" => ["fetch", "execute", "finish"] },
    "params" => {
      "type" => "object",
      "additionalProperties" => true,
      "description" => "Parameters for the action. For 'fetch', YOU MUST provide {'ticker': 'AAPL'}."
    },
    "confidence" => { "type" => "number", "minimum" => 0, "maximum" => 1 }
  }
}

planner = AgentRuntime::Planner.new(
  client: client,
  schema: schema,
  prompt_builder: ->(input:, state:) {
    "User request: #{input}\nContext: #{state.to_json}"
  },
  temperature: 0.1
)

# [!IMPORTANT]
# The `think: true` parameter requires models with native CoT support (e.g., `deepseek-r1`).
# Using it with `llama` or `qwen` models will return an `HTTP 400` error.

agent = AgentRuntime::Agent.new(
  planner: planner,
  policy: AgentRuntime::Policy.new,
  executor: AgentRuntime::Executor.new(tool_registry: tools),
  state: AgentRuntime::State.new,
  audit_log: AgentRuntime::AuditLog.new
)

result = agent.step(input: "Fetch market data for AAPL")
puts result.inspect
```

### Multi-step loop (`Agent#run`)
Use this when the agent should iterate until it emits `finish` or a tool marks
`done: true`. This loop uses `/generate` only (no chat).

```ruby
result = agent.run(initial_input: "Find best PDF library for Ruby")
```

### Formal FSM workflow (`AgentFSM`)
`AgentFSM` is the explicit FSM driver. It uses `/generate` for PLAN and
`/chat` for EXECUTE. Tool execution happens only in OBSERVE.

Tool calling in EXECUTE generates its JSON schemas completely natively based on the definitions you pass into the `ToolRegistry`. You no longer need to subclass anything or define Ollama structures manually.

```ruby
agent_fsm = AgentRuntime::AgentFSM.new(
  planner: planner,
  policy: AgentRuntime::Policy.new,
  executor: AgentRuntime::Executor.new(tool_registry: tools),
  state: AgentRuntime::State.new,
  tool_registry: tools,
  audit_log: AgentRuntime::AuditLog.new
)

result = agent_fsm.run(initial_input: "Research Ruby memory management")
```

### Integrating with MCP (Model Context Protocol)
`AgentRuntime` natively supports executing tools provided by any Model Context Protocol ([MCP](https://modelcontextprotocol.io)) server using the [Ruby MCP SDK](https://github.com/modelcontextprotocol/ruby-sdk)!

To integrate, pass a connected `MCP::Client` directly into your `ToolRegistry` via `#register_mcp_client`. This automatically extracts all the remote tool schemas for the LLM and seamlessly routes execution events back through your MCP connection.

```ruby
require "agent_runtime"
require "mcp"
require "faraday" # Using an HTTP transport for the MCP client

# 1. Connect to any remote or local MCP Server
http_transport = MCP::Client::HTTP.new(url: "https://api.example.com/mcp")
mcp_client = MCP::Client.new(transport: http_transport)

# 2. Register the MCP tools natively into AgentRuntime
tools = AgentRuntime::ToolRegistry.new
tools.register_mcp_client(mcp_client)

# 3. The LLM can now automatically inspect and call remote tools!
agent_fsm = AgentRuntime::AgentFSM.new(tool_registry: tools, ...)
agent_fsm.run(initial_input: "Use the remote tool to get me the weather!")
```

## Tool safety model
- Tools are Ruby callables registered in `ToolRegistry`.
- LLM output never executes tools directly.
- Tool execution happens only in `Executor`.
- Tool results are recorded in state and (for FSM) injected as `role: "tool"`.

## Progress tracking and convergence

AgentRuntime provides generic progress tracking and convergence detection to prevent infinite loops.

### Progress tracking

The `State` includes a `ProgressTracker` that tracks opaque signals. The runtime does not interpret these signals; they are domain-agnostic markers.

```ruby
state = AgentRuntime::State.new
state.progress.mark!(:tool_called)
state.progress.mark!(:step_completed)
state.progress.include?(:tool_called)  # => true
```

The `Executor` automatically marks `:tool_called` and `:step_completed` when tools are executed.

### Convergence policy

By default, agents never converge (safe default). Applications must define convergence logic by overriding `Policy#converged?`:

```ruby
class ConvergentPolicy < AgentRuntime::Policy
  def converged?(state)
    # Converge when required signals are present
    state.progress.include?(:primary_task_done, :validation_complete)
  end
end

policy = ConvergentPolicy.new
agent = AgentRuntime::Agent.new(
  planner: planner,
  policy: policy,  # Use convergent policy
  executor: executor,
  state: state
)

# Agent will halt when policy.converged?(state) returns true
result = agent.run(initial_input: "Complete task")
```

**Important**: Convergence is enforced by policy, not prompts. The runtime does not interpret tool semantics or LLM output to determine completion. Applications define what "done" means through progress signals and convergence logic.

### Why convergence matters

Without convergence detection, agents can loop indefinitely:
- Tool calls succeed forever
- Executor keeps reasoning
- Max steps are exceeded
- No real work is finalized

With convergence:
- Applications track progress via signals
- Policy determines when work is complete
- Runtime halts deterministically
- No reliance on LLM deciding "I'm done"

## Examples

### Quick Start
**Start here**: `examples/complete_working_example.rb` - A complete, runnable example demonstrating all features.

```bash
# Make sure Ollama is running: ollama serve
ruby examples/complete_working_example.rb
```

### Available Examples
- `examples/complete_working_example.rb` ⭐ - **Complete working example** (recommended starting point)
- `examples/fixed_console_example.rb` - Minimal example for console use
- `examples/console_example.rb` - Basic console example
- `examples/rails_example/` - Rails integration example
- `examples/dhanhq_example.rb` - Domain-specific example (requires DhanHQ gem)

See `examples/README.md` for detailed documentation on all examples.

Examples are not part of the public API.

## Documentation

📚 **Comprehensive documentation** is available in the [`docs/`](docs/) directory.

### Quick Links
- **[Agentic Workflows](docs/AGENTIC_WORKFLOWS.md)** - Understanding workflow patterns
- **[FSM Workflows](docs/FSM_WORKFLOWS.md)** - Finite State Machine guide
- **[Schema Guide](docs/SCHEMA_GUIDE.md)** - JSON Schema reference
- **[Prerequisites](docs/PREREQUISITES.md)** - Setup requirements
- **[Testing Guide](docs/TESTING.md)** - Testing and coverage

See [`docs/README.md`](docs/README.md) for complete documentation index.

## Development
After checking out the repo, run:

```bash
bin/setup
```

To run tests:

```bash
rake spec
# or
bundle exec rspec
```

Test coverage reports are generated automatically. View the HTML report:
```bash
open coverage/index.html  # macOS
xdg-open coverage/index.html  # Linux
```

See `TESTING.md` for detailed testing and coverage information.

To run the console:

```bash
bin/console
```

## Contributing
Bug reports and pull requests are welcome. Keep the API strict and small.

## License
The gem is available as open source under the terms of the MIT License.
