# frozen_string_literal: true

module AgentRuntime
  class Agent
    def initialize(planner:, policy:, executor:, state:, audit_log: nil)
      @planner = planner
      @policy = policy
      @executor = executor
      @state = state
      @audit_log = audit_log
    end

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
  end
end
