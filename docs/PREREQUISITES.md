# Prerequisites and Setup

## Ollama Client Dependency

`agent_runtime` depends on the [`ollama-client`](https://github.com/shubhamtaywade82/ollama-client) gem for LLM communication.

### Installation

```bash
gem install ollama-client
```

Or add to your Gemfile:

```ruby
gem "ollama-client"
```

### Client Initialization

The `ollama-client` gem provides `Ollama::Client`:

```ruby
require "ollama_client"

# Basic initialization (uses defaults from environment or global config)
client = Ollama::Client.new

# With custom configuration
config = Ollama::Config.new
config.base_url = "http://localhost:11434"
config.model = "llama3.1:8b"
config.timeout = 30

client = Ollama::Client.new(config: config)
```

### Global Configuration (Optional)

You can configure defaults globally:

```ruby
require "ollama_client"

OllamaClient.configure do |c|
  c.base_url = "http://localhost:11434"
  c.model = "llama3.1:8b"
  c.timeout = 30
  c.retries = 3
  c.temperature = 0.2
end

# Then use simple initialization
client = Ollama::Client.new
```

### Client Interface Requirements

Your `Ollama::Client` instance must support:

- `generate(prompt:, schema:)` - For PLAN state (single-shot, stateless)
- `chat(messages:, allow_chat: true, ...)` - For simple chat responses
- `chat_raw(messages:, tools:, allow_chat: true, ...)` - For tool calling (returns full response with `tool_calls`)

The `ollama-client` gem provides all methods with proper error handling, retries, and schema validation.

**Important:** For tool calling, use `chat_raw()` to get the complete response including `tool_calls`:
```ruby
response = client.chat_raw(messages: messages, tools: tools, allow_chat: true)
tool_calls = response.dig("message", "tool_calls")
```

### API Mapping

| AgentRuntime State | Ollama::Client Method | Endpoint | Purpose |
|-------------------|----------------------|----------|---------|
| PLAN              | `generate(prompt:, schema:)` | `/api/generate` | Single-shot planning |
| EXECUTE           | `chat_raw(messages:, tools:, allow_chat: true)` | `/api/chat` | Tool calling with full response |

### Example: Complete Setup

```ruby
require "agent_runtime"
require "ollama_client"

# 1. Set up tools
tools = AgentRuntime::ToolRegistry.new({
  "fetch" => ->(**args) { { data: "fetched", args: args } },
  "execute" => ->(**args) { { result: "executed", args: args } }
})

# 2. Configure Ollama client
client = Ollama::Client.new

# 3. Create planner (uses generate for PLAN state)
planner = AgentRuntime::Planner.new(
  client: client,
  schema: {
    "type" => "object",
    "required" => ["action", "params", "confidence"],
    "properties" => {
      "action" => { "type" => "string", "enum" => ["fetch", "execute", "analyze", "finish"] },
      "params" => {
        "type" => "object",
        "additionalProperties" => true,
        "description" => "Parameters for the action (any key-value pairs allowed)"
      },
      "confidence" => { "type" => "number", "minimum" => 0, "maximum" => 1 }
    }
  },
  prompt_builder: ->(input:, state:) {
    "User request: #{input}\nContext: #{state.to_json}"
  }
)

# 4. Create agent
agent = AgentRuntime::Agent.new(
  planner: planner,
  policy: AgentRuntime::Policy.new,
  executor: AgentRuntime::Executor.new(tool_registry: tools),
  state: AgentRuntime::State.new
)
```

### Ollama Server

**Important:** Ensure Ollama server is running before using `agent_runtime`:

```bash
# Start Ollama server
ollama serve

# In another terminal, verify it's running
curl http://localhost:11434/api/tags
```

The default URL is `http://localhost:11434`. Set `OLLAMA_URL` environment variable or configure via `Ollama::Config` to use a different server.

**Verify server is accessible:**
```ruby
require "ollama_client"

client = Ollama::Client.new
begin
  models = client.list_models
  puts "✅ Ollama server is running"
  puts "Available models: #{models.join(', ')}"
rescue => e
  puts "❌ Cannot connect to Ollama server: #{e.message}"
  puts "Start the server with: ollama serve"
end
```

**Install a model:**
```bash
ollama pull llama3.1:8b
# or
ollama pull qwen2.5:14b
```

### Error Handling

The `ollama-client` gem provides comprehensive error handling. When using `agent_runtime`, wrap agent calls in error handling:

```ruby
begin
  result = agent.step(input: "Your request")
rescue Ollama::RetryExhaustedError => e
  # Ollama server error after retries (500, 503, etc.)
  puts "Ollama server error: #{e.message}"
  # Check: Is Ollama server running? Is the model available?
rescue Ollama::SchemaViolationError => e
  # Output didn't match schema
  puts "Schema violation: #{e.message}"
rescue Ollama::TimeoutError => e
  # Request timed out
  puts "Request timed out: #{e.message}"
rescue Ollama::NotFoundError => e
  # Model not found
  puts "Model not found: #{e.message}"
  # The error message includes suggestions for similar model names
rescue Ollama::HTTPError => e
  # Other HTTP errors (400, 500, etc.)
  puts "HTTP error: #{e.message}"
rescue AgentRuntime::PolicyViolation => e
  # Policy validation failed
  puts "Policy violation: #{e.message}"
rescue AgentRuntime::ExecutionError => e
  # Agent execution error
  puts "Execution error: #{e.message}"
rescue Ollama::Error => e
  # Other ollama-client errors
  puts "Ollama error: #{e.message}"
end
```

### Troubleshooting Common Issues

#### HTTP 500: Internal Server Error

This usually means:
- Ollama server is not running: `ollama serve`
- Model is not available: `ollama list` to see installed models
- Model name is incorrect: Check `ollama list` for exact model names
- Server is overloaded: Try again or check server logs

**Solution:**
```ruby
# Check if Ollama is accessible
begin
  client = Ollama::Client.new
  models = client.list_models
  puts "Available models: #{models.join(', ')}"
rescue => e
  puts "Cannot connect to Ollama: #{e.message}"
  puts "Make sure Ollama server is running: ollama serve"
end
```

#### Model Not Found

```ruby
# The error message includes suggestions
rescue Ollama::NotFoundError => e
  puts e.message
  # Example output:
  # Model 'llama3.1:8b' not found. Did you mean one of these?
  #   - llama3.1
  #   - llama3.2:3b
```

#### Schema Validation Errors

If you get schema violations, check:
- Schema format is valid JSON Schema
- Model supports structured outputs (most modern models do)
- Prompt is clear about expected output format

```ruby
# Use a simpler schema for testing
simple_schema = {
  "type" => "object",
  "properties" => {
    "action" => { "type" => "string" }
  }
}
```

### Advanced: Using Ollama::Agent Classes

The `ollama-client` gem also provides higher-level agent classes:

- `Ollama::Agent::Planner` - Uses `/api/generate` (stateless)
- `Ollama::Agent::Executor` - Uses `/api/chat` with tools (stateful)

However, `agent_runtime` uses the lower-level `Ollama::Client` directly for maximum flexibility and control.

### Mock Client for Testing

For testing without a real Ollama server:

```ruby
class MockOllamaClient
  def generate(prompt:, schema:)
    {
      "action" => "test",
      "params" => {},
      "confidence" => 0.9
    }
  end

  def chat(messages:, allow_chat: false, **kwargs)
    { "content" => "Mock response" }
  end
end

client = MockOllamaClient.new
```

See the [`ollama-client` documentation](https://github.com/shubhamtaywade82/ollama-client) for complete API reference.
