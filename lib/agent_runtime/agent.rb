# frozen_string_literal: true

module AgentRuntime
  # Simple agent implementation with step-by-step execution and multi-step loops.
  #
  # This class provides a straightforward agent implementation that executes
  # planning, validation, and execution steps in a loop until termination.
  # Use this for simpler workflows where you don't need the full FSM structure.
  #
  # @example Single step execution
  #   agent = AgentRuntime::Agent.new(planner: planner, policy: policy, executor: executor, state: state)
  #   result = agent.step(input: "What is 2+2?")
  #
  # @example Multi-step agentic workflow
  #   agent = AgentRuntime::Agent.new(planner: planner, policy: policy, executor: executor, state: state)
  #   result = agent.run(initial_input: "Find the weather and send an email")
  class Agent
    # Initialize a new Agent instance.
    #
    # @param planner [Planner] The planner responsible for generating decisions
    # @param policy [Policy] The policy validator for decisions
    # @param executor [Executor] The executor for tool calls
    # @param state [State] The state manager for agent state
    # @param audit_log [AuditLog, nil] Optional audit logger for recording decisions
    # @param max_iterations [Integer] Maximum number of iterations before raising an error (default: 50)
    def initialize(planner:, policy:, executor:, state:, audit_log: nil, max_iterations: 50)
      @planner = planner
      @policy = policy
      @executor = executor
      @state = state
      @audit_log = audit_log
      @max_iterations = max_iterations
    end

    # Single step execution (non-agentic).
    #
    # Use this for one-shot decisions or when you control the loop externally.
    # This method performs a single planning, validation, execution, and state update cycle.
    #
    # @param input [String] The input prompt for this step
    # @return [Hash] The execution result hash
    # @raise [PolicyViolation] If the decision violates policy constraints
    # @raise [ExecutionError] If execution fails
    #
    # @example
    #   result = agent.step(input: "Calculate 5 * 10")
    #   # => { result: 50 }
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

    # Agentic workflow loop (runs until termination).
    #
    # Use this for multi-step workflows where the agent decides when to stop.
    # The loop continues until:
    # - The decision action is "finish"
    # - The result contains `done: true`
    # - Maximum iterations are exceeded
    #
    # @param initial_input [String] The initial input to start the workflow
    # @param input_builder [Proc, nil] Optional proc to build next input from result and iteration.
    #   Called as `input_builder.call(result, iteration)`. If nil, uses default builder.
    # @return [Hash] Final result hash, always includes `done: true` and `iterations` count
    # @raise [MaxIterationsExceeded] If maximum iterations are exceeded
    # @raise [PolicyViolation] If any decision violates policy constraints
    # @raise [ExecutionError] If execution fails
    #
    # @example
    #   result = agent.run(initial_input: "Find weather and send email")
    #   # => { done: true, iterations: 3, ... }
    #
    # @example With custom input builder
    #   builder = ->(result, iteration) { "Iteration #{iteration}: #{result.inspect}" }
    #   result = agent.run(initial_input: "Start", input_builder: builder)
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

    # Check if the agent should terminate based on decision and result.
    #
    # @param decision [Decision] The current decision
    # @param result [Hash] The execution result
    # @return [Boolean] True if the agent should terminate
    def terminated?(decision, result)
      decision.action == "finish" || result[:done] == true
    end

    # Build the next input for the loop iteration.
    #
    # @param result [Hash] The previous execution result
    # @param _iteration [Integer] The current iteration number (unused)
    # @return [String] The next input string
    def build_next_input(result, _iteration)
      "Continue based on: #{result.inspect}"
    end
  end
end
