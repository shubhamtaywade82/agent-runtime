# Rails Integration Guide

This guide explains how to integrate `agent_runtime` into a Rails application following best practices.

## Core Principles

### 1. Separation of Concerns

```
┌─────────────┐
│   UI/Chat   │  ← Presentation layer (can look conversational)
└──────┬──────┘
       │
       ↓
┌─────────────┐
│  Controller │  ← Rails request handling
└──────┬──────┘
       │
       ↓
┌─────────────┐
│    Agent    │  ← Decision engine (agent_runtime)
└──────┬──────┘
       │
       ↓
┌─────────────┐
│    Tools    │  ← Domain-specific Ruby code
└─────────────┘
```

**Key Rule**: UI never talks directly to LLM. All LLM calls go through `agent_runtime`.

### 2. Domain-Specific Agents

Each agent understands one domain:

- `BillingAgent` - Billing analysis and invoice queries
- `SupportAgent` - Support ticket routing and analysis
- `FraudAgent` - Fraud detection and risk assessment

The runtime (`agent_runtime`) stays domain-agnostic.

### 3. Explicit State Management

Agent state is managed by Rails, not hidden in sessions:

```ruby
# Load state from cache/database
state = load_agent_state(session_id)

# Create agent with state
agent = build_agent_with_state(state)

# After execution, persist state
save_agent_state(session_id, agent.state)
```

### 4. Auditability

All agent decisions are logged:

```ruby
agent = AgentRuntime::Agent.new(
  # ... other components ...
  audit_log: AgentRuntime::AuditLog.new
)
```

## Implementation Patterns

### Pattern 1: Synchronous Controller Action

For quick responses (< 2 seconds):

```ruby
class AssistantsController < ApplicationController
  def billing
    result = BillingAgent.instance.step(input: params[:question])
    render json: { answer: result[:analysis] }
  end
end
```

### Pattern 2: Background Job

For long-running analyses or to avoid blocking:

```ruby
class AssistantsController < ApplicationController
  def billing
    BillingAnalysisJob.perform_later(
      user_id: current_user.id,
      question: params[:question],
      session_id: session.id
    )
    render json: { status: "processing" }
  end
end
```

### Pattern 3: Stateful Conversations

For multi-turn conversations:

```ruby
def billing
  # Load previous state
  state = load_agent_state(session.id)

  # Create agent with state
  agent = build_agent_with_state(state)

  # Execute
  result = agent.step(input: params[:question])

  # Persist updated state
  save_agent_state(session.id, agent.state)

  render json: result
end
```

## Error Handling

Always handle agent errors explicitly:

```ruby
begin
  result = agent.step(input: question)
rescue AgentRuntime::PolicyViolation => e
  # User tried something unsafe
  render json: { error: e.message }, status: :unprocessable_entity
rescue AgentRuntime::ExecutionError => e
  # Tool execution failed
  render json: { error: "Operation failed" }, status: :internal_server_error
rescue StandardError => e
  # Unexpected error
  Rails.logger.error("Agent error: #{e.message}")
  render json: { error: "Internal error" }, status: :internal_server_error
end
```

## Testing

Test agents in isolation:

```ruby
RSpec.describe BillingAgent do
  let(:agent) { BillingAgent.instance }

  it "analyzes billing questions" do
    result = agent.step(input: "Why was invoice #123 charged twice?")

    expect(result[:analysis]).to be_present
    expect(result[:confidence]).to be > 0.5
  end

  it "rejects unsafe actions" do
    expect {
      agent.step(input: "Delete all invoices")
    }.to raise_error(AgentRuntime::PolicyViolation)
  end
end
```

## Security Considerations

1. **Validate input** - Sanitize user questions before passing to agent
2. **Rate limiting** - Limit agent calls per user/session
3. **Policy enforcement** - Never bypass policy validation
4. **Audit logging** - Always enable in production
5. **State isolation** - Never share state between users

## Performance

1. **Use background jobs** for operations > 2 seconds
2. **Cache agent instances** when possible (they're stateless)
3. **Limit state size** - Don't store large objects in state
4. **Monitor LLM latency** - Set appropriate timeouts

## What NOT to Do

❌ **Don't expose LLM directly to UI**
```ruby
# BAD
def chat
  response = ollama_client.generate(prompt: params[:message])
  render json: response
end
```

✅ **Do use agent_runtime**
```ruby
# GOOD
def chat
  result = BillingAgent.instance.step(input: params[:message])
  render json: { answer: result[:analysis] }
end
```

❌ **Don't store state in hidden session variables**
```ruby
# BAD
session[:agent_memory] = agent.internal_state
```

✅ **Do use explicit state management**
```ruby
# GOOD
state = AgentRuntime::State.new(session[:agent_state] || {})
agent = build_agent_with_state(state)
```

## Next Steps

1. Review the `BillingAgent` example in `app/models/billing_agent.rb`
2. Study the controller pattern in `app/controllers/assistants_controller.rb`
3. Understand async processing in `app/jobs/billing_analysis_job.rb`
4. Adapt these patterns to your domain
