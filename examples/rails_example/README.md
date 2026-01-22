# Rails Integration Example

This example demonstrates how to integrate `agent_runtime` into a Rails application to build a domain-specific assistant.

## ⚠️ Note: Conceptual Example

This is a **conceptual example** showing the integration pattern. It demonstrates the structure and approach, but is not a full working Rails app. Use it as a reference for your own implementation.

## Architecture

```
User → Rails Controller → Background Job → AgentRuntime::Agent → Tools → Result → UI
```

## Key Principles

1. **UI never talks directly to LLM** - All LLM calls go through `agent_runtime`
2. **Agents are domain-specific** - Each agent understands one domain (billing, support, etc.)
3. **State is explicit** - Agent state is managed by Rails, not hidden in sessions
4. **Decisions are auditable** - All agent decisions are logged via `AuditLog`

## Files

- `app/models/billing_agent.rb` - **✅ UPDATED** Domain-specific agent with correct schema
- `app/controllers/assistants_controller.rb` - Rails controller exposing agent API
- `app/jobs/billing_analysis_job.rb` - Background job for async processing
- `INTEGRATION_GUIDE.md` - **Comprehensive integration guide** (start here!)

## Quick Start

### 1. Review the Integration Guide

Start with `INTEGRATION_GUIDE.md` for comprehensive patterns and best practices.

### 2. Study the Example Agent

See `app/models/billing_agent.rb` for a complete agent implementation:
- ✅ Correct JSON Schema format
- ✅ Domain-specific policy (BillingPolicy) with convergence logic
- ✅ Domain-specific executor with tools
- ✅ Singleton pattern for reuse
- ✅ Convergence policy to prevent infinite loops

### 3. Understand Controller Integration

See `app/controllers/assistants_controller.rb` for:
- ✅ Synchronous agent execution (single-step and multi-step)
- ✅ Error handling (PolicyViolation, ExecutionError)
- ✅ JSON response formatting
- ✅ Progress signal tracking and convergence status

### 4. Learn Background Job Pattern

See `app/jobs/billing_analysis_job.rb` for:
- ✅ Async agent execution (single-step and multi-step)
- ✅ State persistence (Redis/cache)
- ✅ Result notification
- ✅ Convergence logging for monitoring

## Usage Examples

### Synchronous Controller Action

```ruby
class AssistantsController < ApplicationController
  def billing
    result = BillingAgent.instance.step(input: params[:question])
    render json: { answer: result[:analysis] }
  rescue AgentRuntime::PolicyViolation => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
```

### Background Job Processing

```ruby
# Queue the job
BillingAnalysisJob.perform_later(
  user_id: current_user.id,
  question: "Why was invoice #123 charged twice?"
)

# Job processes asynchronously
class BillingAnalysisJob < ApplicationJob
  def perform(user_id:, question:, session_id: nil)
    agent = build_agent_with_state(load_agent_state(session_id))
    result = agent.step(input: question)
    notify_user(user, result)
  end
end
```

### Stateful Conversations

```ruby
# Load previous state
state = load_agent_state(session.id)
agent = build_agent_with_state(state)

# Execute with state
result = agent.step(input: params[:question])

# Persist updated state
save_agent_state(session.id, agent.state)
```

### Single-Step vs Multi-Step Execution

```ruby
# Single-step: one decision, one execution (faster, simpler)
result = agent.step(input: "Analyze invoice #123")

# Multi-step: loop until convergence or max iterations (for complex workflows)
result = agent.run(initial_input: "Fetch invoice #123 and analyze it")

# Check convergence status
if agent.state.respond_to?(:progress)
  puts "Progress signals: #{agent.state.progress.signals.inspect}"
  puts "Converged: #{agent.policy.converged?(agent.state)}"
end
```

## Convergence & Progress Tracking

The `BillingPolicy` includes a `converged?` method that prevents infinite loops by defining when the agent has achieved its goal. The runtime automatically tracks progress signals when tools are executed.

**Key Points:**
- ✅ Progress signals are automatically marked when tools execute (`:tool_called`, `:step_completed`)
- ✅ Convergence policy is checked after each step in multi-step workflows (`agent.run()`)
- ✅ Agent halts when `policy.converged?(state)` returns `true` or max iterations are reached
- ✅ Backward compatible: works with or without progress tracking

## Key Components

### BillingAgent (Domain-Specific Agent)

```ruby
class BillingAgent
  def self.instance
    @instance ||= build
  end

  def self.build
    AgentRuntime::Agent.new(
      planner: planner_with_schema,
      policy: BillingPolicy.new,  # Domain-specific
      executor: BillingExecutor.new,  # Domain-specific
      state: AgentRuntime::State.new,
      audit_log: AgentRuntime::AuditLog.new
    )
  end
end
```

### BillingPolicy (Custom Policy)

```ruby
class BillingPolicy < AgentRuntime::Policy
  def validate!(decision, state:)
    super  # Call parent validation

    # Domain-specific validation
    allowed_actions = %w[analyze fetch_invoice finish]
    unless allowed_actions.include?(decision.action)
      raise AgentRuntime::PolicyViolation, "Action not allowed"
    end
  end

  # Convergence policy: prevent infinite loops
  def converged?(state)
    return false unless state.respond_to?(:progress)

    # Converge when we have required data or tool was called
    snapshot = state.snapshot
    has_analysis = snapshot[:analysis].present?
    has_invoice = snapshot[:invoice].present?

    (has_analysis || has_invoice) || state.progress.include?(:tool_called)
  end
end
```

### BillingExecutor (Domain Tools)

```ruby
class BillingExecutor < AgentRuntime::Executor
  def initialize
    tools = AgentRuntime::ToolRegistry.new(
      "analyze" => method(:analyze_billing),
      "fetch_invoice" => method(:fetch_invoice)
    )
    super(tool_registry: tools)
  end

  private

  def analyze_billing(invoice_id:, customer_id:, explanation:)
    # Domain-specific analysis logic
  end

  def fetch_invoice(invoice_id:)
    # Fetch from your database
  end
end
```

## Environment Setup

```bash
# Required environment variables
export OLLAMA_URL=http://localhost:11434
export OLLAMA_MODEL=llama3.1:8b

# Start Ollama server
ollama serve

# Pull model
ollama pull llama3.1:8b
```

## Testing

```ruby
RSpec.describe BillingAgent do
  it "analyzes billing questions" do
    result = BillingAgent.instance.step(
      input: "Why was invoice #123 charged twice?"
    )

    expect(result[:analysis]).to be_present
  end

  it "enforces policy" do
    expect {
      BillingAgent.instance.step(input: "Delete all invoices")
    }.to raise_error(AgentRuntime::PolicyViolation)
  end
end
```

## Next Steps

1. **Read INTEGRATION_GUIDE.md** - Comprehensive patterns and best practices
2. **Adapt BillingAgent** - Replace with your domain logic
3. **Implement your tools** - Add domain-specific tool methods
4. **Define your policy** - Add custom validation rules
5. **Test thoroughly** - Test agent decisions and error handling

## Security Notes

- ✅ Always validate user input before passing to agent
- ✅ Implement rate limiting on agent endpoints
- ✅ Never bypass policy validation
- ✅ Enable audit logging in production
- ✅ Isolate state between users/sessions

## Resources

- Main README: `../../README.md`
- Integration Guide: `INTEGRATION_GUIDE.md`
- Working Example: `../complete_working_example.rb`
- Test Suite: `../../test_agent_workflow.rb`
