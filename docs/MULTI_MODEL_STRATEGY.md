# Multi-Model Strategy for AgentRuntime

## The Problem Most People Get Wrong

**Don't use one model for everything.** Different cognitive states need different models.

This guide shows how to implement production-grade multi-model workflows using AgentRuntime's FSM.

---

## 🧠 Mental Model: Think in States, Not Features

| State | What Happens | Risk if Wrong | Model Need |
|-------|--------------|---------------|------------|
| **PLAN** | Reasoning, analysis | Medium | Smart reasoning |
| **DECIDE** | Validation, rule-checking | **HIGH** | Strict, literal |
| **EXECUTE** | Tool calls | Low | Fast, cheap |
| **FINALIZE** | Human explanation | Low | Good summarization |

**Only 2-3 states need intelligence.** Everything else should be cheap and fast.

---

## ✅ Model Selection Matrix (Ollama)

### Primary Reasoning (PLAN State)

**Use:** `llama3.1:8b`

**Why:**
- Strong structural reasoning
- Excellent instruction-following
- Stable JSON output
- Handles multi-level hierarchy
- Fast enough on CPU/GPU

**Settings:**
```ruby
config.temperature = 0.1
config.num_predict = 400
```

**Task Example:**
```
Infer market_bias, regime, directional_allowance
from structured SMC + AVRZ data
```

---

### Strict Validation (DECIDE State)

**Use:** `llama3.1:8b` (same model as reasoning) OR `qwen2.5:7b`

**Why:**
- With `temperature: 0.0`, even the same model becomes deterministic
- Strict rule adherence
- Excellent for YES/NO/CONFLICT logic
- Zero hallucination due to deterministic output

**Key Insight:** You can use the SAME model for different cognitive states by varying temperature:
- Reasoning: `temperature: 0.1` (slight creativity for structured thinking)
- Validation: `temperature: 0.0` (absolute determinism for YES/NO decisions)

**Settings:**
```ruby
config.temperature = 0.0  # Absolute determinism
```

**Task Example:**
```
Does this :call decision violate HTF bias?
Answer: ALLOW or BLOCK
```

This is your **compliance officer**, not an analyst.

---

### Human Explanation (FINALIZE State)

**Use:** `llama3.2:3b` (or `llama3.1:8b` if you want consistency)

**Why:**
- Cheap and fast
- Good summarization
- Doesn't overthink
- No new reasoning

**Settings:**
```ruby
config.temperature = 0.3
```

**Task Example:**
```
Summarize this decision in 1-2 lines for Telegram.
No new reasoning. Just summarize.
```

---

### Fallback/Circuit-Breaker

**Use:** `qwen2.5:7b-instruct`

**When:** Primary model fails schema

This is your "AI went stupid" backup.

---

## 🚫 What NOT to Use

| Model | Why It's Bad |
|-------|--------------|
| `mixtral` | Oververbose, too creative |
| `llama3:70b` | Slow, ego-driven answers |
| `deepseek-r1` | Over-reasoning, breaks JSON |
| Vision models | Useless for structured data |
| Streaming | No need for batch decisions |

---

## 🧩 Recommended Pipeline

```
Market Data
    ↓
llama3.1:8b-instruct (PLAN)
→ Bias + Regime reasoning
    ↓
qwen2.5:7b-instruct (DECIDE)
→ Decision validation (ALLOW/BLOCK)
    ↓
EXECUTE (if allowed)
→ Tool calls (no model needed)
    ↓
llama3.1:4b-instruct (FINALIZE)
→ Human summary for Telegram
```

Each model has **one job**. No overlap.

---

## 💻 Implementation with AgentRuntime

### 1. Create Multiple Clients

```ruby
# REASONING MODEL
reasoning_config = Ollama::Config.new
reasoning_config.model = "llama3.1:8b-instruct"
reasoning_config.temperature = 0.1
reasoning_client = Ollama::Client.new(config: reasoning_config)

# VALIDATION MODEL
validation_config = Ollama::Config.new
validation_config.model = "qwen2.5:7b-instruct"
validation_config.temperature = 0.0  # Deterministic
validation_client = Ollama::Client.new(config: validation_config)

# EXPLANATION MODEL
explanation_config = Ollama::Config.new
explanation_config.model = "llama3.1:4b-instruct"
explanation_config.temperature = 0.3
explanation_client = Ollama::Client.new(config: explanation_config)
```

### 2. Create State-Specific Planners

```ruby
reasoning_planner = AgentRuntime::Planner.new(
  client: reasoning_client,
  schema: reasoning_schema,
  prompt_builder: reasoning_prompt
)

validation_planner = AgentRuntime::Planner.new(
  client: validation_client,
  schema: validation_schema,
  prompt_builder: validation_prompt
)

explanation_planner = AgentRuntime::Planner.new(
  client: explanation_client
  # No schema - just text generation
)
```

### 3. Create Multi-Model FSM

```ruby
class MultiModelAgentFSM < AgentRuntime::AgentFSM
  def initialize(reasoning_planner:, validation_planner:, explanation_planner:, **opts)
    @reasoning_planner = reasoning_planner
    @validation_planner = validation_planner
    @explanation_planner = explanation_planner
    super(**opts)
  end

  # Override PLAN to use reasoning model
  def handle_plan
    plan_result = @reasoning_planner.plan(
      input: @messages.first[:content],
      state: @state.snapshot
    )

    # Store analysis in state
    @state.apply!({ analysis: plan_result.params })

    @fsm.transition_to(FSM::STATES[:DECIDE], reason: "Analysis complete")
  end

  # Override DECIDE to use validation model
  def handle_decide
    validation_result = @validation_planner.plan(
      input: "Validate signal",
      state: @state.snapshot
    )

    decision = validation_result.params
    @state.apply!({ validation: decision })

    if decision[:decision] == "ALLOW"
      @fsm.transition_to(FSM::STATES[:EXECUTE], reason: "Validated")
    else
      @fsm.transition_to(FSM::STATES[:HALT], reason: "Blocked")
    end
  end

  # Override FINALIZE to use explanation model
  def handle_finalize
    summary = @explanation_planner.chat(
      messages: [{
        role: "user",
        content: "Summarize: #{@state.snapshot.to_json}"
      }]
    )

    {
      done: true,
      summary: summary,
      analysis: @state.snapshot[:analysis],
      validation: @state.snapshot[:validation]
    }
  end
end
```

### 4. Use It

```ruby
agent = MultiModelAgentFSM.new(
  reasoning_planner: reasoning_planner,
  validation_planner: validation_planner,
  explanation_planner: explanation_planner,
  # ... other components
)

result = agent.run(initial_input: "Analyze SPY CALL signal")

# result contains:
# - analysis from reasoning model
# - validation from validation model
# - summary from explanation model
```

---

## 🔒 Hard Engineering Rules

### 1. Never Reuse Models Across States

❌ **Bad:**
```ruby
planner = Planner.new(client: client)  # Same for everything
```

✅ **Good:**
```ruby
reasoning_planner = Planner.new(client: reasoning_client)
validation_planner = Planner.new(client: validation_client)
```

### 2. Schema Violation = Block Trade

```ruby
begin
  result = planner.plan(input: data, state: state)
rescue Ollama::RetryExhaustedError => e
  # Schema failed after retries = HALT
  return { decision: "BLOCK", reason: "Schema violation" }
end
```

### 3. HTF Dominance in Code, Not AI

```ruby
class TradingPolicy < AgentRuntime::Policy
  def validate!(decision, state:)
    super

    htf_bias = state.snapshot.dig(:analysis, :htf_bias)
    signal = decision.params[:signal_type]

    # Code enforcement, not AI discretion
    if htf_bias == "bearish" && signal == "call"
      raise PolicyViolation, "HTF bias forbids calls"
    end
  end
end
```

### 4. AI OFF Must Still Work

```ruby
class SafeExecutor
  def execute(decision, state:)
    return fallback_logic(decision, state) unless ai_enabled?

    # AI-enhanced logic
  end

  private

  def fallback_logic(decision, state)
    # Pure rule-based system
  end
end
```

### 5. Never Retry Same Model Blindly

```ruby
# ❌ Bad: Retry same model hoping for different result
3.times { planner.plan(...) }

# ✅ Good: Use fallback model
begin
  primary_planner.plan(...)
rescue SchemaError
  fallback_planner.plan(...)  # Different model
end
```

---

## 📊 Cost & Latency Benchmarks

Typical production setup (1 signal/5min):

| State | Model | Latency | Cost/Month |
|-------|-------|---------|------------|
| PLAN | llama3.1:8b | ~2s | $0 (local) |
| DECIDE | qwen2.5:7b | ~1s | $0 (local) |
| FINALIZE | llama3.1:4b | ~0.5s | $0 (local) |

**Total per signal:** ~3.5s, $0

With Ollama, you're **not paying API fees**. The cost is:
- Hardware (CPU/GPU)
- Power consumption
- Minimal compared to OpenAI/Anthropic

---

## 🧪 Testing the Strategy

### Test Each Model Independently

```ruby
RSpec.describe "Multi-Model Strategy" do
  describe "Reasoning Model" do
    it "infers correct market bias" do
      result = reasoning_planner.plan(
        input: market_data,
        state: State.new
      )

      expect(result.params[:market_bias]).to be_in(%w[bullish bearish neutral])
      expect(result.params[:confidence]).to be_between(0, 1)
    end
  end

  describe "Validation Model" do
    it "blocks conflicting signals" do
      state = State.new({
        analysis: {
          market_bias: "bearish",
          htf_bias: "bearish"
        }
      })

      result = validation_planner.plan(
        input: "Validate CALL signal",
        state: state
      )

      expect(result.params[:decision]).to eq("BLOCK")
    end
  end
end
```

### Test the Assembly

```ruby
describe MultiModelAgentFSM do
  it "uses correct model for each state" do
    allow(reasoning_planner).to receive(:plan).and_call_original
    allow(validation_planner).to receive(:plan).and_call_original

    agent.run(initial_input: "Analyze signal")

    expect(reasoning_planner).to have_received(:plan).once
    expect(validation_planner).to have_received(:plan).once
  end
end
```

---

## 🎯 Real-World Example: Trading System

```ruby
# Setup
reasoning = create_reasoning_planner
validation = create_validation_planner
explanation = create_explanation_planner

agent = MultiModelAgentFSM.new(
  reasoning_planner: reasoning,
  validation_planner: validation,
  explanation_planner: explanation,
  policy: TradingPolicy.new,
  executor: TradingExecutor.new,
  state: State.new,
  max_iterations: 10
)

# Every 5 minutes
loop do
  market_data = fetch_smc_and_avrz_data

  result = agent.run(initial_input: market_data.to_json)

  if result[:validation][:decision] == "ALLOW"
    send_telegram_alert(result[:summary])
    execute_trade(result[:analysis])
  else
    log_blocked_signal(result[:validation][:reason])
  end

  sleep(300)  # 5 minutes
end
```

---

## 📚 See Also

- **Working Example:** `examples/multi_model_strategy.rb`
- **FSM Guide:** `docs/FSM_WORKFLOWS.md`
- **Custom Policy:** `docs/AGENTIC_WORKFLOWS.md`
- **Main README:** `README.md`

---

## 🏆 Final Verdict

You don't want a **smart AI**. You want a **disciplined AI assembly line**.

> One model to think
> One model to say "NO"
> One model to explain

That's how you survive production.

---

**Last Updated:** 2026-01-16
