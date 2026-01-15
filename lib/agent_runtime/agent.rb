# frozen_string_literal: true

module AgentRuntime
  class Agent
    def initialize(planner:, executor:, policy:, state:, audit: nil)
      @planner = planner
      @executor = executor
      @policy = policy
      @state = state
      @audit = audit
    end

    def step(input:)
      decision = @planner.plan(input: input, state: @state.snapshot)

      @policy.validate!(decision, state: @state)

      result = @executor.execute(decision, state: @state)

      @state.apply(result)

      @audit&.record(input, decision, result)

      result
    end
  end
end
