# frozen_string_literal: true

module AgentRuntime
  # Formal Finite State Machine for agentic workflows
  # Implements the canonical agentic workflow FSM with 8 states
  class FSM
    STATES = {
      INTAKE: 0,
      PLAN: 1,
      DECIDE: 2,
      EXECUTE: 3,
      OBSERVE: 4,
      LOOP_CHECK: 5,
      FINALIZE: 6,
      HALT: 7
    }.freeze

    TERMINAL_STATES = [STATES[:FINALIZE], STATES[:HALT]].freeze

    def initialize(max_iterations: 50)
      @state = STATES[:INTAKE]
      @max_iterations = max_iterations
      @iteration_count = 0
      @history = []
    end

    attr_reader :state, :iteration_count, :history

    def intake?
      @state == STATES[:INTAKE]
    end

    def plan?
      @state == STATES[:PLAN]
    end

    def decide?
      @state == STATES[:DECIDE]
    end

    def execute?
      @state == STATES[:EXECUTE]
    end

    def observe?
      @state == STATES[:OBSERVE]
    end

    def loop_check?
      @state == STATES[:LOOP_CHECK]
    end

    def finalize?
      @state == STATES[:FINALIZE]
    end

    def halt?
      @state == STATES[:HALT]
    end

    def terminal?
      TERMINAL_STATES.include?(@state)
    end

    def transition_to(new_state, reason: nil)
      validate_transition(@state, new_state)
      @history << { from: @state, to: new_state, reason: reason, iteration: @iteration_count }
      @state = new_state
    end

    def increment_iteration
      @iteration_count += 1
      raise MaxIterationsExceeded, "Max iterations (#{@max_iterations}) exceeded" if @iteration_count > @max_iterations
    end

    def reset
      @state = STATES[:INTAKE]
      @iteration_count = 0
      @history = []
    end

    def state_name
      STATES.key(@state) || "UNKNOWN"
    end

    private

    # Valid transitions based on FSM specification
    # INTAKE → PLAN
    # PLAN → DECIDE | HALT
    # DECIDE → EXECUTE | FINALIZE | HALT
    # EXECUTE → OBSERVE | FINALIZE | HALT
    # OBSERVE → LOOP_CHECK
    # LOOP_CHECK → EXECUTE | FINALIZE | HALT
    # FINALIZE → (terminal)
    # HALT → (terminal)
    VALID_TRANSITIONS = {
      STATES[:INTAKE] => [STATES[:PLAN]],
      STATES[:PLAN] => [STATES[:DECIDE], STATES[:HALT]],
      STATES[:DECIDE] => [STATES[:EXECUTE], STATES[:FINALIZE], STATES[:HALT]],
      STATES[:EXECUTE] => [STATES[:OBSERVE], STATES[:FINALIZE], STATES[:HALT]],
      STATES[:OBSERVE] => [STATES[:LOOP_CHECK]],
      STATES[:LOOP_CHECK] => [STATES[:EXECUTE], STATES[:FINALIZE], STATES[:HALT]],
      STATES[:FINALIZE] => [],
      STATES[:HALT] => []
    }.freeze

    def validate_transition(from, to)
      return if VALID_TRANSITIONS[from]&.include?(to)

      raise ExecutionError, "Invalid transition from #{state_name_for(from)} to #{state_name_for(to)}"
    end

    def state_name_for(state_value)
      STATES.key(state_value) || "UNKNOWN"
    end
  end
end
