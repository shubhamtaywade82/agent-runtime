# frozen_string_literal: true

module AgentRuntime
  # Formal Finite State Machine for agentic workflows.
  #
  # Implements the canonical agentic workflow FSM with 8 states:
  # - INTAKE: Normalize input, initialize state
  # - PLAN: Single-shot planning using /generate
  # - DECIDE: Make bounded decision (continue vs stop)
  # - EXECUTE: LLM proposes next actions using /chat (looping state)
  # - OBSERVE: Execute tools, inject real-world results
  # - LOOP_CHECK: Control continuation
  # - FINALIZE: Produce terminal output (terminal state)
  # - HALT: Abort safely (terminal state)
  #
  # Valid state transitions:
  # - INTAKE → PLAN
  # - PLAN → DECIDE | HALT
  # - DECIDE → EXECUTE | FINALIZE | HALT
  # - EXECUTE → OBSERVE | FINALIZE | HALT
  # - OBSERVE → LOOP_CHECK
  # - LOOP_CHECK → EXECUTE | FINALIZE | HALT
  # - FINALIZE → (terminal)
  # - HALT → (terminal)
  #
  # @example Initialize and use FSM
  #   fsm = FSM.new(max_iterations: 100)
  #   fsm.transition_to(FSM::STATES[:PLAN], reason: "Starting")
  #   fsm.plan?  # => true
  #
  # @see AgentFSM
  class FSM
    # State constants mapping state names to integer values.
    #
    # @return [Hash<Symbol, Integer>] Hash of state names to integer values
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

    # Terminal states that cannot transition to other states.
    #
    # @return [Array<Integer>] Array of terminal state values
    TERMINAL_STATES = [STATES[:FINALIZE], STATES[:HALT]].freeze

    # Valid state transitions based on FSM specification.
    #
    # Maps each state to an array of valid next states.
    #
    # @return [Hash<Integer, Array<Integer>>] Hash mapping state values to arrays of valid next states
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

    # Initialize a new FSM instance.
    #
    # @param max_iterations [Integer] Maximum number of iterations before raising an error (default: 50)
    def initialize(max_iterations: 50)
      @state = STATES[:INTAKE]
      @max_iterations = max_iterations
      @iteration_count = 0
      @history = []
    end

    # @!attribute [r] state
    #   @return [Integer] Current state value
    # @!attribute [r] iteration_count
    #   @return [Integer] Current iteration count
    # @!attribute [r] history
    #   @return [Array<Hash>] Array of transition history entries with :from, :to, :reason, :iteration
    attr_reader :state, :iteration_count, :history

    # Check if current state is INTAKE.
    #
    # @return [Boolean] True if in INTAKE state
    def intake?
      @state == STATES[:INTAKE]
    end

    # Check if current state is PLAN.
    #
    # @return [Boolean] True if in PLAN state
    def plan?
      @state == STATES[:PLAN]
    end

    # Check if current state is DECIDE.
    #
    # @return [Boolean] True if in DECIDE state
    def decide?
      @state == STATES[:DECIDE]
    end

    # Check if current state is EXECUTE.
    #
    # @return [Boolean] True if in EXECUTE state
    def execute?
      @state == STATES[:EXECUTE]
    end

    # Check if current state is OBSERVE.
    #
    # @return [Boolean] True if in OBSERVE state
    def observe?
      @state == STATES[:OBSERVE]
    end

    # Check if current state is LOOP_CHECK.
    #
    # @return [Boolean] True if in LOOP_CHECK state
    def loop_check?
      @state == STATES[:LOOP_CHECK]
    end

    # Check if current state is FINALIZE.
    #
    # @return [Boolean] True if in FINALIZE state
    def finalize?
      @state == STATES[:FINALIZE]
    end

    # Check if current state is HALT.
    #
    # @return [Boolean] True if in HALT state
    def halt?
      @state == STATES[:HALT]
    end

    # Check if current state is terminal (FINALIZE or HALT).
    #
    # @return [Boolean] True if in a terminal state
    def terminal?
      TERMINAL_STATES.include?(@state)
    end

    # Transition to a new state.
    #
    # Validates the transition and records it in history.
    #
    # @param new_state [Integer] The state value to transition to
    # @param reason [String, nil] Optional reason for the transition (recorded in history)
    # @return [void]
    # @raise [ExecutionError] If the transition is invalid
    #
    # @example
    #   fsm.transition_to(FSM::STATES[:PLAN], reason: "Input normalized")
    def transition_to(new_state, reason: nil)
      validate_transition(@state, new_state)
      @history << { from: @state, to: new_state, reason: reason, iteration: @iteration_count }
      @state = new_state
    end

    # Increment the iteration count.
    #
    # @return [void]
    # @raise [MaxIterationsExceeded] If iteration count exceeds maximum
    def increment_iteration
      @iteration_count += 1
      raise MaxIterationsExceeded, "Max iterations (#{@max_iterations}) exceeded" if @iteration_count > @max_iterations
    end

    # Reset the FSM to initial state.
    #
    # Resets state to INTAKE, clears iteration count and history.
    #
    # @return [void]
    def reset
      @state = STATES[:INTAKE]
      @iteration_count = 0
      @history = []
    end

    # Get the name of the current state.
    #
    # @return [Symbol, String] State name symbol or "UNKNOWN" if state value is invalid
    def state_name
      STATES.key(@state) || "UNKNOWN"
    end

    # Validate a state transition.
    #
    # @param from [Integer] The source state value
    # @param to [Integer] The target state value
    # @return [void]
    # @raise [ExecutionError] If the transition is invalid
    def validate_transition(from, to)
      return if VALID_TRANSITIONS[from]&.include?(to)

      raise ExecutionError, "Invalid transition from #{state_name_for(from)} to #{state_name_for(to)}"
    end

    # Get the name for a state value.
    #
    # @param state_value [Integer] The state value
    # @return [Symbol, String] State name symbol or "UNKNOWN" if state value is invalid
    def state_name_for(state_value)
      STATES.key(state_value) || "UNKNOWN"
    end
  end
end
