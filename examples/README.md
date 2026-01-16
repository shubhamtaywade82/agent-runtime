# AgentRuntime Examples

This directory contains working examples demonstrating how to use the AgentRuntime gem.

## Quick Start Example

The simplest way to get started is with the **complete working example**:

```bash
# Make sure Ollama is running
ollama serve

# In another terminal, run the example
ruby examples/complete_working_example.rb
```

This example demonstrates:
- ✅ Setting up tools
- ✅ Configuring Ollama client
- ✅ Creating a planner with schema
- ✅ Using Agent for single-step execution
- ✅ Using Agent for multi-step workflows
- ✅ Using AgentFSM for formal FSM workflows

## Available Examples

### `complete_working_example.rb` ⭐ **START HERE**
**Complete, runnable example** that demonstrates all major features.

**What it shows:**
- Tool registry setup
- Ollama client configuration
- Schema definition for structured output
- Prompt builder implementation
- Single-step agent execution
- Multi-step agent workflows
- AgentFSM with tool calling

**Run it:**
```bash
ruby examples/complete_working_example.rb
```

### `fixed_console_example.rb`
Minimal example for use in `bin/console`. Copy-paste ready.

**Use it:**
```bash
./bin/console
# Then copy-paste the contents of fixed_console_example.rb
```

### `console_example.rb`
Basic console example (may need schema fixes).

### `dhanhq_example.rb`
Domain-specific example for Indian market data (requires DhanHQ gem).

### `rails_example/`
Complete Rails integration example showing:
- Domain-specific agent (BillingAgent)
- Rails controller integration
- Background job processing
- State persistence

## Example Patterns

### Pattern 1: Simple Agent (Single Step)

```ruby
require "agent_runtime"
require "ollama_client"

# 1. Define tools
tools = AgentRuntime::ToolRegistry.new({
  "search" => ->(query:) { { results: "Found: #{query}" } }
})

# 2. Setup Ollama
client = Ollama::Client.new

# 3. Create planner
planner = AgentRuntime::Planner.new(
  client: client,
  schema: { /* your schema */ },
  prompt_builder: ->(input:, state:) { "Prompt: #{input}" }
)

# 4. Create agent
agent = AgentRuntime::Agent.new(
  planner: planner,
  policy: AgentRuntime::Policy.new,
  executor: AgentRuntime::Executor.new(tool_registry: tools),
  state: AgentRuntime::State.new
)

# 5. Execute
result = agent.step(input: "Search for Ruby")
```

### Pattern 2: Multi-Step Agent

```ruby
# Same setup as Pattern 1, then:
result = agent.run(initial_input: "Search and analyze")
# Agent will loop until "finish" action or done: true
```

### Pattern 3: AgentFSM (Formal FSM)

```ruby
# Same setup, but use AgentFSM:
agent_fsm = AgentRuntime::AgentFSM.new(
  planner: planner,
  policy: AgentRuntime::Policy.new,
  executor: executor,
  state: state,
  tool_registry: tools
)

result = agent_fsm.run(initial_input: "Complete workflow")
# Follows formal FSM: INTAKE -> PLAN -> DECIDE -> EXECUTE -> OBSERVE -> ...
```

## Key Concepts

### Tools
Tools are Ruby callables (procs, lambdas, or objects with `#call`):

```ruby
tools = AgentRuntime::ToolRegistry.new({
  "my_tool" => ->(param1:, param2:) do
    # Your tool logic here
    { result: "processed" }
  end
})
```

### Schema
Schema defines the structure of LLM decisions:

```ruby
schema = {
  "type" => "object",
  "required" => ["action", "params"],
  "properties" => {
    "action" => {
      "type" => "string",
      "enum" => ["search", "calculate", "finish"]
    },
    "params" => {
      "type" => "object",
      "additionalProperties" => true
    }
  }
}
```

### Prompt Builder
Prompt builder creates prompts from user input and state:

```ruby
prompt_builder = ->(input:, state:) do
  "User: #{input}\nState: #{state.to_json}"
end
```

## Testing Your Setup

Run the integration tests to verify everything works:

```bash
# Run all tests (unit + integration)
bundle exec rspec

# Run only integration tests
INTEGRATION=true bundle exec rspec spec/integration/
```

## Troubleshooting

### "Ollama server error"
- Make sure Ollama is running: `ollama serve`
- Check if the model exists: `ollama list`
- Pull a model if needed: `ollama pull llama3.1:8b`

### "Model not found"
- Update the model name in the example to match your available models
- Check available models: `ollama list`

### "Policy violation"
- Check that your LLM response includes required fields (action, params)
- Verify confidence is >= 0.5 if provided

### "Tool not found"
- Ensure tool names in schema match tool registry keys
- Check that tools are registered before creating the executor

## Next Steps

1. **Customize for your domain**: Replace example tools with your own
2. **Adjust schema**: Define actions specific to your use case
3. **Implement custom Policy**: Add domain-specific validation rules
4. **Add audit logging**: Implement custom AuditLog for your storage
5. **See documentation**: Check `README.md`, `AGENTIC_WORKFLOWS.md`, `FSM_WORKFLOWS.md`
