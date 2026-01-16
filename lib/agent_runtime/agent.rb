# frozen_string_literal: true

module AgentRuntime
  # Simple agent implementation with step-by-step execution and multi-step loops
  class Agent
    def initialize(planner:, policy:, executor:, state:, audit_log: nil, max_iterations: 50)
      @planner = planner
      @policy = policy
      @executor = executor
      @state = state
      @audit_log = audit_log
      @max_iterations = max_iterations
    end

    # Single step execution (non-agentic)
    # Use this for one-shot decisions or when you control the loop externally
    def step(input:)
      decision = @planner.plan(
        input: input,
        state: @state.snapshot
      )

      @policy.validate!(decision, state: @state)

      result = @executor.execute(decision, state: @state)

      @state.apply!(result)

      @audit_log&.record(
        input: input,
        decision: decision,
        result: result
      )

      result
    end

    # Agentic workflow loop (runs until termination)
    # Use this for multi-step workflows where the agent decides when to stop
    def run(initial_input:, input_builder: nil)
      iteration = 0
      current_input = initial_input
      final_result = nil

      loop do
        iteration += 1

        raise MaxIterationsExceeded, "Max iterations (#{@max_iterations}) exceeded" if iteration > @max_iterations

        decision = @planner.plan(
          input: current_input,
          state: @state.snapshot
        )

        @policy.validate!(decision, state: @state)

        result = @executor.execute(decision, state: @state)

        @state.apply!(result)

        @audit_log&.record(
          input: current_input,
          decision: decision,
          result: result
        )

        # Always set final_result before checking termination
        final_result = result

        break if terminated?(decision, result)

        current_input = input_builder ? input_builder.call(result, iteration) : build_next_input(result, iteration)
      end

      final_result || { done: true, iterations: iteration }
    end

    private

    def terminated?(decision, result)
      decision.action == "finish" || result[:done] == true
    end

    def build_next_input(result, _iteration)
      "Continue based on: #{result.inspect}"
    end
  end
end
