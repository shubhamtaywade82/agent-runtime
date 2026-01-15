# Testing Guide for agent_runtime

This guide covers different ways to test `agent_runtime`, from quick manual tests to comprehensive automated test suites.

## Quick Start: Manual Testing

### 1. Using the Console

The fastest way to test is using the provided console example:

```bash
# Start the console
./bin/console

# Then load the example
load 'examples/fixed_console_example.rb'
```

Or copy-paste the code from `examples/fixed_console_example.rb` directly into your console session.

### 2. Using the Fixed Example Script

```bash
# Make sure Ollama is running first
ollama serve

# In another terminal, run the example
ruby examples/fixed_console_example.rb
```

## Automated Testing

### Running Existing Tests

```bash
# Run all RSpec tests
bundle exec rspec

# Run with documentation format
bundle exec rspec --format documentation

# Run specific test file
bundle exec rspec spec/agent_runtime_spec.rb

# Run with coverage (if configured)
bundle exec rspec --format documentation
```

### Test Structure

Tests are located in `spec/` directory:
- `spec/spec_helper.rb` - Test configuration
- `spec/agent_runtime_spec.rb` - Main test file (currently minimal)

## Writing Tests

### Unit Tests with Mocks

For unit tests, you should mock the Ollama client to avoid requiring a running Ollama server:

```ruby
# spec/agent_runtime/planner_spec.rb
require "spec_helper"

RSpec.describe AgentRuntime::Planner do
  let(:mock_client) { instance_double("Ollama::Client") }
  let(:schema) do
    {
      "type" => "object",
      "required" => ["action", "params"],
      "properties" => {
        "action" => { "type" => "string" },
        "params" => { "type" => "object", "additionalProperties" => true }
      }
    }
  end
  let(:prompt_builder) { ->(input:, state:) { "Prompt: #{input}" } }
  let(:planner) { described_class.new(client: mock_client, schema: schema, prompt_builder: prompt_builder) }

  describe "#plan" do
    it "returns a Decision from client.generate response" do
      response = { "action" => "fetch", "params" => { "symbol" => "AAPL" } }
      allow(mock_client).to receive(:generate).and_return(response)

      decision = planner.plan(input: "Fetch AAPL", state: {})

      expect(decision).to be_a(AgentRuntime::Decision)
      expect(decision.action).to eq("fetch")
      expect(decision.params).to eq({ "symbol" => "AAPL" })
    end

    it "raises error when schema is missing" do
      planner_without_schema = described_class.new(client: mock_client)
      expect { planner_without_schema.plan(input: "test", state: {}) }
        .to raise_error(AgentRuntime::ExecutionError, /schema and prompt_builder/)
    end
  end
end
```

### Integration Tests with Real Ollama

For integration tests that actually call Ollama, you'll need a running Ollama server:

```ruby
# spec/integration/agent_integration_spec.rb
require "spec_helper"
require "ollama_client"

RSpec.describe "Agent Integration", type: :integration do
  before(:all) do
    # Skip if Ollama is not available
    begin
      @client = Ollama::Client.new
      @client.list_models
    rescue StandardError
      skip "Ollama server not available"
    end
  end

  let(:client) { @client }
  let(:tools) do
    AgentRuntime::ToolRegistry.new({
      "fetch" => ->(**args) { { data: "fetched", args: args } }
    })
  end

  let(:schema) do
    {
      "type" => "object",
      "required" => ["action", "params", "confidence"],
      "properties" => {
        "action" => {
          "type" => "string",
          "enum" => ["fetch", "finish"]
        },
        "params" => {
          "type" => "object",
          "additionalProperties" => true
        },
        "confidence" => {
          "type" => "number",
          "minimum" => 0,
          "maximum" => 1
        }
      }
    }
  end

  let(:planner) do
    AgentRuntime::Planner.new(
      client: client,
      schema: schema,
      prompt_builder: ->(input:, state:) {
        "User request: #{input}\nRespond with action and params."
      }
    )
  end

  let(:agent) do
    AgentRuntime::Agent.new(
      planner: planner,
      policy: AgentRuntime::Policy.new,
      executor: AgentRuntime::Executor.new(tool_registry: tools),
      state: AgentRuntime::State.new
    )
  end

  it "executes a single step successfully" do
    result = agent.step(input: "Fetch data for AAPL")
    expect(result).to be_a(Hash)
    expect(result).to have_key(:data)
  end
end
```

### Testing Individual Components

#### Testing ToolRegistry

```ruby
# spec/agent_runtime/tool_registry_spec.rb
require "spec_helper"

RSpec.describe AgentRuntime::ToolRegistry do
  let(:tools) do
    described_class.new({
      "fetch" => ->(**args) { { data: "fetched", args: args } },
      "execute" => ->(**args) { { result: "executed" } }
    })
  end

  describe "#call" do
    it "calls the registered tool" do
      result = tools.call("fetch", symbol: "AAPL")
      expect(result[:data]).to eq("fetched")
      expect(result[:args][:symbol]).to eq("AAPL")
    end

    it "raises error for unknown tool" do
      expect { tools.call("unknown") }.to raise_error(AgentRuntime::ExecutionError)
    end
  end
end
```

#### Testing State

```ruby
# spec/agent_runtime/state_spec.rb
require "spec_helper"

RSpec.describe AgentRuntime::State do
  let(:state) { described_class.new }

  describe "#apply!" do
    it "merges new data into state" do
      state.apply!({ key: "value" })
      expect(state.snapshot[:key]).to eq("value")
    end

    it "deep merges nested hashes" do
      state.apply!({ nested: { a: 1 } })
      state.apply!({ nested: { b: 2 } })
      expect(state.snapshot[:nested]).to eq({ a: 1, b: 2 })
    end
  end

  describe "#snapshot" do
    it "returns a copy of current state" do
      state.apply!({ key: "value" })
      snapshot = state.snapshot
      snapshot[:new_key] = "new_value"
      expect(state.snapshot[:new_key]).to be_nil
    end
  end
end
```

#### Testing Policy

```ruby
# spec/agent_runtime/policy_spec.rb
require "spec_helper"

RSpec.describe AgentRuntime::Policy do
  let(:policy) { described_class.new }
  let(:decision) { AgentRuntime::Decision.new(action: "fetch", params: {}, confidence: 0.9) }

  describe "#validate!" do
    it "passes for valid decision" do
      expect { policy.validate!(decision, state: {}) }.not_to raise_error
    end

    it "raises error for missing action" do
      invalid_decision = AgentRuntime::Decision.new(params: {}, confidence: 0.9)
      expect { policy.validate!(invalid_decision, state: {}) }
        .to raise_error(AgentRuntime::PolicyViolation)
    end
  end
end
```

## Test Helpers

Create a test helper for common setup:

```ruby
# spec/support/agent_helpers.rb
module AgentHelpers
  def build_mock_ollama_client
    instance_double("Ollama::Client").tap do |client|
      allow(client).to receive(:generate).and_return({
        "action" => "fetch",
        "params" => {},
        "confidence" => 0.9
      })
      allow(client).to receive(:chat).and_return({ "content" => "Response" })
      allow(client).to receive(:chat_raw).and_return({
        "message" => { "content" => "Response", "tool_calls" => [] }
      })
    end
  end

  def build_test_schema
    {
      "type" => "object",
      "required" => ["action", "params", "confidence"],
      "properties" => {
        "action" => {
          "type" => "string",
          "enum" => ["fetch", "execute", "finish"]
        },
        "params" => {
          "type" => "object",
          "additionalProperties" => true
        },
        "confidence" => {
          "type" => "number",
          "minimum" => 0,
          "maximum" => 1
        }
      }
    }
  end

  def build_test_planner(client: nil, schema: nil)
    client ||= build_mock_ollama_client
    schema ||= build_test_schema
    AgentRuntime::Planner.new(
      client: client,
      schema: schema,
      prompt_builder: ->(input:, state:) { "Prompt: #{input}" }
    )
  end
end

RSpec.configure do |config|
  config.include AgentHelpers
end
```

## Running Tests in CI/CD

For CI/CD, you can use Docker to run Ollama:

```yaml
# .github/workflows/test.yml
name: Test

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      ollama:
        image: ollama/ollama:latest
        ports:
          - 11434:11434
    steps:
      - uses: actions/checkout@v3
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.3
      - run: bundle install
      - run: bundle exec rspec
```

## Best Practices

1. **Mock external dependencies**: Use mocks for Ollama client in unit tests
2. **Tag integration tests**: Use `type: :integration` to separate slow tests
3. **Test behavior, not implementation**: Focus on what the code does, not how
4. **Use descriptive test names**: Test names should describe the behavior being tested
5. **Keep tests fast**: Unit tests should run in milliseconds
6. **Test edge cases**: Empty inputs, nil values, invalid schemas, etc.
7. **Test error handling**: Verify proper error messages and exception types

## Example: Complete Test Suite Structure

```
spec/
├── spec_helper.rb
├── support/
│   ├── agent_helpers.rb
│   └── ollama_helpers.rb
├── agent_runtime/
│   ├── agent_spec.rb
│   ├── agent_fsm_spec.rb
│   ├── planner_spec.rb
│   ├── executor_spec.rb
│   ├── policy_spec.rb
│   ├── state_spec.rb
│   ├── tool_registry_spec.rb
│   └── decision_spec.rb
└── integration/
    └── agent_integration_spec.rb
```

## Quick Test Checklist

Before committing, verify:

- [ ] All unit tests pass: `bundle exec rspec`
- [ ] Code style is clean: `bundle exec rubocop`
- [ ] Manual test works: `ruby examples/fixed_console_example.rb`
- [ ] Integration tests pass (if Ollama is available)
- [ ] No linter errors: `bundle exec rubocop -a`
