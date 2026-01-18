# Schema Design Guide

This guide explains how to design JSON schemas for `agent_runtime` that work correctly with the `ollama-client` gem.

## Key Principle: `additionalProperties`

By default, `ollama-client` enforces **strict schema validation** - object schemas reject extra properties unless explicitly allowed.

### The Problem

If your schema defines:
```ruby
"params" => { "type" => "object" }
```

The LLM cannot add any properties to `params` (like `symbol`, `query`, etc.) because `additionalProperties` defaults to `false`.

### The Solution

Always set `"additionalProperties" => true` for dynamic parameter objects:

```ruby
schema = {
  "type" => "object",
  "required" => ["action", "params", "confidence"],
  "properties" => {
    "action" => { "type" => "string", "enum" => ["fetch", "execute", "finish"] },
    "params" => {
      "type" => "object",
      "additionalProperties" => true,  # ← CRITICAL: Allows LLM to add any properties
      "description" => "Parameters for the action"
    },
    "confidence" => { "type" => "number", "minimum" => 0, "maximum" => 1 }
  }
}
```

## Common Patterns

### Pattern 1: Flexible Parameters (Recommended)

Use this when the LLM needs to pass different parameters for different actions:

```ruby
{
  "type" => "object",
  "required" => ["action", "params"],
  "properties" => {
    "action" => { "type" => "string", "enum" => ["search", "fetch", "analyze"] },
    "params" => {
      "type" => "object",
      "additionalProperties" => true,  # LLM can add: symbol, query, url, etc.
      "description" => "Action-specific parameters"
    }
  }
}
```

**Example LLM output:**
```json
{
  "action": "fetch",
  "params": {
    "symbol": "AAPL",
    "exchange": "NASDAQ"
  }
}
```

### Pattern 2: Strict Parameters

Use this when you want to enforce specific parameter structure:

```ruby
{
  "type" => "object",
  "required" => ["action", "params"],
  "properties" => {
    "action" => { "type" => "string", "enum" => ["fetch"] },
    "params" => {
      "type" => "object",
      "required" => ["symbol"],
      "properties" => {
        "symbol" => { "type" => "string" },
        "exchange" => { "type" => "string", "enum" => ["NASDAQ", "NYSE"] }
      },
      "additionalProperties" => false  # Only symbol and exchange allowed
    }
  }
}
```

### Pattern 3: Mixed Structure

Combine fixed fields with flexible params:

```ruby
{
  "type" => "object",
  "required" => ["action", "reasoning", "params"],
  "properties" => {
    "action" => { "type" => "string", "enum" => ["search", "fetch"] },
    "reasoning" => { "type" => "string" },
    "params" => {
      "type" => "object",
      "additionalProperties" => true  # Flexible
    }
  }
}
```

## Error: "contains additional properties"

If you see this error:
```
The property '#/params' contains additional properties ["symbol"] outside of the schema when none are allowed
```

**Fix:** Add `"additionalProperties" => true` to the object schema:

```ruby
# ❌ WRONG - too strict
"params" => { "type" => "object" }

# ✅ CORRECT - allows extra properties
"params" => {
  "type" => "object",
  "additionalProperties" => true
}
```

## Best Practices

1. **Use `additionalProperties: true` for dynamic params** - When the LLM needs flexibility
2. **Use `additionalProperties: false` for fixed structures** - When you want strict validation
3. **Always provide descriptions** - Helps the LLM understand what to include
4. **Use enums for actions** - Prevents invalid action names
5. **Set min/max for numbers** - Prevents out-of-range values

## Example: Complete Working Schema

```ruby
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
      "additionalProperties" => true,  # ← Allows LLM to add symbol, query, etc.
      "description" => "Parameters for the action (e.g., symbol, query, url)"
    },
    "confidence" => {
      "type" => "number",
      "minimum" => 0,
      "maximum" => 1,
      "description" => "Confidence level in this decision"
    }
  }
}
```

This schema allows the LLM to return:
```json
{
  "action": "fetch",
  "params": {
    "symbol": "AAPL",
    "exchange": "NASDAQ"
  },
  "confidence": 0.9
}
```

Without `additionalProperties: true`, the LLM cannot add `symbol` or `exchange` to `params`.
