# Example Usage Tests

This directory contains tests that verify the usage patterns demonstrated in the `examples/` directory work correctly.

## Purpose

These tests ensure that:
1. The documented usage patterns in examples actually work
2. The multi-model strategy pattern is correctly implemented
3. The basic Agent and AgentFSM usage patterns function as expected
4. Users can rely on the examples as working reference implementations

## Test Files

### `multi_model_strategy_spec.rb`

Tests the multi-model strategy pattern from `examples/multi_model_strategy.rb`:

- ✅ Uses different models for different cognitive states (PLAN, DECIDE, FINALIZE)
- ✅ Verifies reasoning model is used for PLAN state
- ✅ Verifies validation model is used for DECIDE state
- ✅ Verifies explanation model is used for FINALIZE state
- ✅ Tests complete workflow with all three models
- ✅ Tests signal blocking when validation fails
- ✅ Validates state-specific schema structures

### `complete_working_example_spec.rb`

Tests the basic usage patterns from `examples/complete_working_example.rb`:

- ✅ Agent#step usage with different actions (search, calculate, get_time, finish)
- ✅ Agent#run multi-step workflow pattern
- ✅ AgentFSM full workflow pattern
- ✅ State persistence across steps
- ✅ Error handling patterns

## Running the Tests

These tests are marked as `type: :integration` and use mocked Ollama clients to avoid requiring a real Ollama server.

To run all example tests:

```bash
INTEGRATION=true bundle exec rspec spec/examples/
```

To run a specific test file:

```bash
INTEGRATION=true bundle exec rspec spec/examples/multi_model_strategy_spec.rb
INTEGRATION=true bundle exec rspec spec/examples/complete_working_example_spec.rb
```

## Test Strategy

These tests use **mocked Ollama clients** rather than real API calls because:

1. **Reliability**: Tests don't depend on external services
2. **Speed**: Tests run quickly without network calls
3. **Determinism**: Tests produce consistent results
4. **Focus**: Tests verify usage patterns, not LLM behavior

The mocks verify that:
- Correct methods are called on the clients
- Correct models are used for each state
- Correct parameters are passed
- State transitions work as expected
- Results are properly structured

## Relationship to Examples

These tests **complement** the actual example files:

- **Examples** (`examples/*.rb`): Runnable scripts that demonstrate usage with real Ollama
- **Tests** (`spec/examples/*_spec.rb`): Automated verification that the patterns work

Both are valuable:
- Examples show how to use the gem in practice
- Tests ensure the patterns continue to work as the codebase evolves

## Adding New Example Tests

When adding a new example, consider adding a corresponding test:

1. Create `spec/examples/your_example_spec.rb`
2. Mark it as `type: :integration`
3. Use mocked clients to test the usage pattern
4. Verify the key behaviors demonstrated in the example
5. Follow Clean Ruby principles (clear names, single responsibility, etc.)

## Clean Ruby Principles Applied

These tests follow Clean Ruby principles:

- **Clear names**: Test descriptions clearly state what behavior is being verified
- **Single responsibility**: Each test verifies one specific behavior
- **No duplication**: Common setup is extracted to `let` blocks
- **Readable**: Test structure mirrors the example code structure
- **Maintainable**: Changes to examples are reflected in tests
