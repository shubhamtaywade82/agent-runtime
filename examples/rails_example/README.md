# Rails Integration Example

This example demonstrates how to integrate `agent_runtime` into a Rails application to build a domain-specific assistant.

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

- `app/models/billing_agent.rb` - Domain-specific agent setup
- `app/controllers/assistants_controller.rb` - Rails controller exposing agent
- `app/jobs/billing_analysis_job.rb` - Background job for async processing
- `config/initializers/agent_runtime.rb` - Agent configuration

## Usage

```ruby
# In a controller
result = BillingAgent.instance.step(input: "Why was invoice #123 charged twice?")

# In a background job
BillingAnalysisJob.perform_later(user_id: current_user.id, question: params[:question])
```
