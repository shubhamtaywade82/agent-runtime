# Ollama Model Allocation for Alerts + Bias + Validation

This guide specifies a production model map for a multi-stage alert pipeline.
Reasoning, validation, and explanation are separated across dedicated models.

## State map

| State | Responsibility | Risk if wrong |
| --- | --- | --- |
| Ingest | Read JSON | Low |
| Reason | Infer bias and regime | Medium |
| Validate | Allow or block decision | High |
| Explain | Human summary | Low |
| Store | Persist result | None |

Only Reason and Validate require intelligence. All other states stay deterministic.

## Model selection matrix

| State | Model | Purpose | Notes |
| --- | --- | --- | --- |
| Reason | llama3.1:8b-instruct | Bias, regime, directional allowance | temperature 0.1, num_predict 400 |
| Validate | qwen2.5:7b-instruct | Alignment check (yes/no/conflict) | Strict, literal responses |
| Explain | llama3.1:4b-instruct | 1-2 line summary from final JSON | No new reasoning |
| Emergency | qwen2.5:7b-instruct | Schema fallback | Only if primary fails schema |

## Pipeline

SMC + AVRZ structure
  -> llama3.1:8b-instruct (bias + regime)
  -> qwen2.5:7b-instruct (alignment check)
  -> allow / block
  -> llama3.1:4b-instruct (telegram summary)

## Ollama pull commands

ollama pull llama3.1:8b-instruct
ollama pull qwen2.5:7b-instruct
ollama pull llama3.1:4b-instruct

## Hard engineering rules

1. Never reuse a model across states.
2. Never retry the same model blindly.
3. Schema violation means block trade.
4. AI off must keep the pipeline running with safe defaults.
5. HTF dominance is enforced in code, not AI.

## Models to avoid

- mixtral: verbose, creative
- llama3:70b: slow, verbose
- deepseek-r1: over-reasoning, unstable JSON
- vision models: not used here
- embedding models: inputs are already structured
- streaming: no need for streaming output
