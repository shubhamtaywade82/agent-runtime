# Console Testing Guide

Quick guide for testing `agent_runtime` in the interactive console.

## Starting the Console

```bash
./bin/console
```

This starts an IRB session with `agent_runtime` already loaded.

## Quick Test Setup

### Option 1: Load the Fixed Example

```ruby
# In console, type:
load 'examples/fixed_console_example.rb'
```

This will:
- Set up tools
- Configure Ollama client
- Create planner with correct schema
- Create agent
- Run a test step

### Option 2: Step-by-Step Manual Setup

Copy and paste this into your console:

```ruby
require "ollama_client"

# 1. Check Ollama is running
client = Ollama::Client.new
begin
  models = client.list_models
  puts "✅ Ollama running. Models: #{models.join(', ')}"
rescue => e
  puts "❌ Ollama not accessible: #{e.message}"
  exit
end

# 2. Set up tools
tools = AgentRuntime::ToolRegistry.new({
  "fetch" => ->(**args) { { data: "fetched", args: args } },
  "execute" => ->(**args) { { result: "executed", args: args } }
})

# 3. Configure client with model
config = Ollama::Config.new
config.model = "llama3.1:8b"  # Use your available model
client = Ollama::Client.new(config: config)

# 4. Create schema (full JSON Schema format)
schema = {
  "type" => "object",
  "required" => ["action", "params", "confidence"],
  "properties" => {
    "action" => {
      "type" => "string",
      "enum" => ["fetch", "execute", "analyze", "finish"],
      "description" => "The action to take"
    },
    "params" => {
      "type" => "object",
      "additionalProperties" => true,
      "description" => "Parameters for the action"
    },
    "confidence" => {
      "type" => "number",
      "minimum" => 0,
      "maximum" => 1,
      "description" => "Confidence level"
    }
  }
}

# 5. Create planner
planner = AgentRuntime::Planner.new(
  client: client,
  schema: schema,
  prompt_builder: ->(input:, state:) {
    "User request: #{input}\nContext: #{state.to_json}\nRespond with action, params, and confidence."
  }
)

# 6. Create agent
agent = AgentRuntime::Agent.new(
  planner: planner,
  executor: AgentRuntime::Executor.new(tool_registry: tools),
  policy: AgentRuntime::Policy.new,
  state: AgentRuntime::State.new,
  audit_log: AgentRuntime::AuditLog.new
)

# 7. Test it!
result = agent.step(input: "Fetch market data for AAPL")
puts result.inspect
```

## Common Testing Patterns

### Test Single Step

```ruby
result = agent.step(input: "Your request here")
puts result
```

### Test Multiple Steps

```ruby
result1 = agent.step(input: "Fetch data for AAPL")
puts "Step 1: #{result1}"

result2 = agent.step(input: "Analyze the fetched data")
puts "Step 2: #{result2}"
```

### Check Agent State

```ruby
# View current state
agent.instance_variable_get(:@state).snapshot

# Or if you kept a reference:
state.snapshot
```

### Test Different Inputs

```ruby
inputs = [
  "Fetch market data for AAPL",
  "Execute analysis on the data",
  "Finish the task"
]

inputs.each do |input|
  result = agent.step(input: input)
  puts "#{input} => #{result.inspect}"
end
```

### Test with Custom Tools

```ruby
# Define custom tools
custom_tools = AgentRuntime::ToolRegistry.new({
  "calculate" => ->(**args) {
    a = args[:a] || 0
    b = args[:b] || 0
    { result: a + b }
  },
  "lookup" => ->(**args) {
    { value: "Found: #{args[:key]}" }
  }
})

# Create new executor with custom tools
executor = AgentRuntime::Executor.new(tool_registry: custom_tools)

# Create agent with custom executor
agent = AgentRuntime::Agent.new(
  planner: planner,
  executor: executor,
  policy: AgentRuntime::Policy.new,
  state: AgentRuntime::State.new
)

# Test
result = agent.step(input: "Calculate 5 + 3")
```

### Test Error Handling

```ruby
begin
  result = agent.step(input: "Invalid request")
rescue Ollama::RetryExhaustedError => e
  puts "Ollama error: #{e.message}"
rescue AgentRuntime::PolicyViolation => e
  puts "Policy violation: #{e.message}"
rescue => e
  puts "Error: #{e.class}: #{e.message}"
end
```

### Inspect Decision Before Execution

```ruby
# Get the decision without executing
decision = planner.plan(input: "Fetch AAPL", state: state.snapshot)
puts "Action: #{decision.action}"
puts "Params: #{decision.params}"
puts "Confidence: #{decision.confidence}"
```

### Test AgentFSM (Full Workflow)

```ruby
# Set up for FSM
tool_registry = AgentRuntime::ToolRegistry.new({
  "fetch" => ->(**args) { { data: "fetched" } }
})

agent_fsm = AgentRuntime::AgentFSM.new(
  planner: planner,
  policy: AgentRuntime::Policy.new,
  executor: AgentRuntime::Executor.new(tool_registry: tool_registry),
  state: AgentRuntime::State.new,
  tool_registry: tool_registry
)

# Run full workflow
result = agent_fsm.run(initial_input: "Fetch market data for AAPL")
puts result.inspect
```

## Debugging Tips

### Check What Model is Being Used

```ruby
client.instance_variable_get(:@config).model
```

### View Planner Schema

```ruby
planner.instance_variable_get(:@schema)
```

### Check Tool Registry

```ruby
tools.instance_variable_get(:@tools).keys
```

### Inspect State History

```ruby
state.snapshot
```

### Test Prompt Builder Directly

```ruby
prompt = planner.instance_variable_get(:@prompt_builder).call(
  input: "Test input",
  state: {}
)
puts prompt
```

## DhanHQ Integration (Indian Markets)

If you have DhanHQ configured, you can test with real Indian market data:

```ruby
# Build DhanHQ agent (requires DhanHQ tools from ollama-client examples)
dhan_agent = build_dhanhq_agent

# Test with Indian market queries
test_dhanhq_agent(dhan_agent, "Get LTP of RELIANCE")
test_dhanhq_agent(dhan_agent, "Find instrument details for NIFTY")
test_dhanhq_agent(dhan_agent, "Get market quote for TCS on NSE_EQ")
```

Or load the standalone example:
```ruby
load 'examples/dhanhq_example.rb'
```

**Prerequisites:**
- DhanHQ gem installed
- DhanHQ tools available at `/home/nemesis/project/ollama-client/examples/dhanhq_tools.rb`
- DhanHQ credentials set in ENV (CLIENT_ID, ACCESS_TOKEN)

## Quick Reference

| Component | How to Create |
|-----------|---------------|
| Tools | `AgentRuntime::ToolRegistry.new({ "name" => ->(**args) { ... } })` |
| Planner | `AgentRuntime::Planner.new(client:, schema:, prompt_builder:)` |
| Executor | `AgentRuntime::Executor.new(tool_registry: tools)` |
| Policy | `AgentRuntime::Policy.new` |
| State | `AgentRuntime::State.new` |
| Agent | `AgentRuntime::Agent.new(planner:, executor:, policy:, state:)` |
| AgentFSM | `AgentRuntime::AgentFSM.new(planner:, executor:, policy:, state:, tool_registry:)` |

## Troubleshooting

### "Ollama server error: HTTP 500"
- Check Ollama is running: `ollama serve`
- Verify model exists: `ollama list`
- Check schema format (must be full JSON Schema)

### "Model not found"
- List available models: `ollama list`
- Update model name in config: `config.model = "your-model:tag"`

### "Schema violation"
- Ensure schema is full JSON Schema format
- Check `additionalProperties: true` for flexible params
- Verify enum values match what LLM might return

### "Policy violation"
- Check policy allows the action
- Verify decision has required fields
