# AgentRuntime Examples

This directory contains example implementations demonstrating how to use AgentRuntime for different domains and integration patterns.

## Available Examples

### Rails Integration (`rails_example/`)
**Complete Rails application integration** showing how to embed agents in web applications.

- Domain-specific agent (BillingAgent)
- Rails controller exposing agent through API
- Background job for async processing
- State persistence per user/session
- Proper error handling and audit logging

**Key Pattern**: UI → Controller → Agent → Tools → Result

### Trading Agent (`dhanhq_agent/`)
A trading agent that uses market data and executes trades through a broker API.

### Patch Agent (`patch_agent/`)
A code refactoring agent that applies patches to codebases safely.

## Structure

Each example follows the same pattern:

1. **Tools**: Domain-specific tool implementations
2. **Policy**: Safety constraints for the domain
3. **Schema**: Decision schema for the LLM
4. **Agent Setup**: Complete agent configuration

## Integration Patterns

### Web Application Integration

For Rails or similar frameworks:

1. **Never expose LLM directly to UI** - All calls go through `agent_runtime`
2. **Agents are domain-specific** - One agent per domain (billing, support, etc.)
3. **State is explicit** - Managed by your application, not hidden in sessions
4. **Use background jobs** - For long-running analyses or to avoid blocking requests

See `rails_example/` for a complete working example.
