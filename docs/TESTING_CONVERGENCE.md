# Testing Convergence Feature

This guide shows how to test that the convergence feature is working correctly.

## Quick Test Script

Run the comprehensive test script:

```bash
ruby -Ilib examples/test_convergence.rb
```

This script tests:
1. ✅ Progress tracking functionality
2. ✅ Convergence policy behavior
3. ✅ Executor automatic signal emission
4. ✅ Agent convergence halting
5. ✅ Multi-signal convergence

## Running Unit Tests

### All Convergence Tests

```bash
bundle exec rspec spec/agent_runtime/progress_tracker_spec.rb spec/agent_runtime/convergence_spec.rb
```

### Individual Test Suites

```bash
# ProgressTracker tests
bundle exec rspec spec/agent_runtime/progress_tracker_spec.rb

# Convergence integration tests
bundle exec rspec spec/agent_runtime/convergence_spec.rb
```

### Full Test Suite

```bash
bundle exec rspec
```

All 280 tests should pass, including the new convergence tests.

## Manual Testing

### 1. Test Progress Tracking

```ruby
require "agent_runtime"

state = AgentRuntime::State.new

# Mark progress signals
state.progress.mark!(:task_started)
state.progress.mark!(:data_fetched)

# Check signals
state.progress.include?(:task_started)  # => true
state.progress.include?(:task_started, :data_fetched)  # => true
state.progress.signals  # => [:task_started, :data_fetched]
```

### 2. Test Convergence Policy

```ruby
# Default policy never converges
policy = AgentRuntime::Policy.new
policy.converged?(state)  # => false

# Custom convergent policy
class MyConvergentPolicy < AgentRuntime::Policy
  def converged?(state)
    state.progress.include?(:work_complete)
  end
end

convergent_policy = MyConvergentPolicy.new
convergent_policy.converged?(state)  # => false (no signal yet)

state.progress.mark!(:work_complete)
convergent_policy.converged?(state)  # => true
```

### 3. Test Executor Signal Emission

```ruby
tools = AgentRuntime::ToolRegistry.new({
  "test_tool" => ->(message:) { { result: message } }
})

executor = AgentRuntime::Executor.new(tool_registry: tools)
state = AgentRuntime::State.new

decision = AgentRuntime::Decision.new(
  action: "test_tool",
  params: { message: "test" }
)

executor.execute(decision, state: state)

# Signals automatically marked
state.progress.include?(:tool_called)  # => true
state.progress.include?(:step_completed)  # => true
```

### 4. Test Agent Convergence

```ruby
# Create a policy that converges after tool is called
class ToolCalledPolicy < AgentRuntime::Policy
  def converged?(state)
    state.progress.include?(:tool_called)
  end
end

# Set up agent with convergent policy
agent = AgentRuntime::Agent.new(
  planner: planner,
  policy: ToolCalledPolicy.new,
  executor: executor,
  state: state,
  max_iterations: 10
)

# Run agent - should halt after first tool call
result = agent.run(initial_input: "Do work")

# Verify it converged
state.progress.include?(:tool_called)  # => true
result[:iterations]  # => 1 (converged after first step)
```

## Integration Test with Real Agent

Here's a complete example that tests convergence end-to-end:

```ruby
require "agent_runtime"
require "ollama_client"

# Set up tools
tools = AgentRuntime::ToolRegistry.new({
  "search" => ->(query:) { { results: "Found: #{query}" } },
  "process" => ->(data:) { { processed: data } }
})

# Set up Ollama client (or use mock)
client = Ollama::Client.new

# Create planner
planner = AgentRuntime::Planner.new(
  client: client,
  schema: schema,
  prompt_builder: ->(input:, state:) { "Prompt: #{input}" }
)

# Create convergent policy
class WorkCompletePolicy < AgentRuntime::Policy
  def converged?(state)
    # Converge when both search and process are done
    state.progress.include?(:search_done, :process_done)
  end
end

# Create agent
agent = AgentRuntime::Agent.new(
  planner: planner,
  policy: WorkCompletePolicy.new,
  executor: AgentRuntime::Executor.new(tool_registry: tools),
  state: AgentRuntime::State.new,
  max_iterations: 10
)

# Mark progress as work progresses (in your application logic)
# This would happen in your tool implementations or after tool calls
state.progress.mark!(:search_done)  # After search tool
state.progress.mark!(:process_done)  # After process tool

# Agent will halt when converged
result = agent.run(initial_input: "Search and process data")
```

## What to Verify

When testing convergence, verify:

1. **Progress Tracking**
   - ✅ Signals can be marked
   - ✅ Signals can be checked
   - ✅ Multiple signals can be checked together
   - ✅ Progress persists across state updates

2. **Convergence Policy**
   - ✅ Default policy never converges
   - ✅ Custom policy can check signals
   - ✅ Custom policy can check multiple signals
   - ✅ Custom policy can check state content

3. **Executor Signals**
   - ✅ `:tool_called` is marked when tools execute
   - ✅ `:step_completed` is marked when tools execute
   - ✅ `finish` action doesn't mark signals

4. **Agent Behavior**
   - ✅ Agent halts when policy indicates convergence
   - ✅ Agent still respects max_iterations
   - ✅ Agent still respects `finish` action
   - ✅ Agent still respects `done: true` result

## Troubleshooting

### Progress tracker not accessible

Make sure you're requiring the gem correctly:

```ruby
require "agent_runtime"  # Not just require_relative
```

Or use:

```bash
ruby -Ilib -r agent_runtime your_script.rb
```

### Convergence not working

1. Check that your policy's `converged?` method is being called
2. Verify signals are being marked in state.progress
3. Ensure you're using the same state instance in policy and agent
4. Check that convergence check happens after tool execution

### Tests failing

Run with verbose output:

```bash
bundle exec rspec spec/agent_runtime/convergence_spec.rb --format documentation
```

Check that all mocks allow `converged?` to be called:

```ruby
allow(mock_policy).to receive(:converged?).and_return(false)
```
