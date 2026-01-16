# frozen_string_literal: true

require "json"
require "securerandom"

module AgentRuntime
  # Agentic workflow implementation using formal FSM.
  #
  # Maps directly to the canonical agentic workflow specification with 8 states:
  # - INTAKE: Normalize input, initialize state
  # - PLAN: Single-shot planning using /generate
  # - DECIDE: Make bounded decision (continue vs stop)
  # - EXECUTE: LLM proposes next actions using /chat (looping state)
  # - OBSERVE: Execute tools, inject real-world results
  # - LOOP_CHECK: Control continuation
  # - FINALIZE: Produce terminal output (terminal state)
  # - HALT: Abort safely (terminal state)
  #
  # This implementation provides a complete agentic workflow with explicit state
  # transitions, tool execution, and audit logging.
  #
  # @example Basic usage
  #   agent_fsm = AgentFSM.new(
  #     planner: planner,
  #     policy: policy,
  #     executor: executor,
  #     state: state,
  #     tool_registry: tools
  #   )
  #   result = agent_fsm.run(initial_input: "Analyze this data")
  #
  # @see FSM
  # @see Agent
  class AgentFSM
    # Initialize a new AgentFSM instance.
    #
    # @param planner [Planner] The planner for generating plans and chat responses
    # @param policy [Policy] The policy validator for decisions
    # @param executor [Executor] The executor for tool calls (currently unused, tools called directly)
    # @param state [State] The state manager for agent state
    # @param tool_registry [ToolRegistry] The registry containing available tools
    # @param audit_log [AuditLog, nil] Optional audit logger for recording decisions
    # @param max_iterations [Integer] Maximum number of iterations before raising an error (default: 50)
    def initialize(planner:, policy:, executor:, state:, tool_registry:, audit_log: nil, max_iterations: 50)
      @planner = planner
      @policy = policy
      @executor = executor
      @state = state
      @tool_registry = tool_registry
      @audit_log = audit_log
      @fsm = FSM.new(max_iterations: max_iterations)
      @messages = []
      @plan = nil
      @decision = nil
    end

    # Run the complete agentic workflow from INTAKE to FINALIZE/HALT.
    #
    # Executes the full FSM workflow, transitioning through all states until
    # reaching a terminal state (FINALIZE or HALT). The workflow handles planning,
    # decision-making, tool execution, and observation in a structured loop.
    #
    # @param initial_input [String] The initial input to start the workflow
    # @return [Hash] Final result hash containing:
    #   - done: Boolean indicating completion status
    #   - iterations: Number of iterations executed
    #   - state: Final state snapshot
    #   - fsm_history: Array of state transition history
    #   - final_message: Optional final message content (if FINALIZE)
    #   - error: Error reason (if HALT)
    # @raise [ExecutionError] If the workflow halts due to an error
    # @raise [MaxIterationsExceeded] If maximum iterations are exceeded
    #
    # @example
    #   result = agent_fsm.run(initial_input: "Find weather and send email")
    #   # => { done: true, iterations: 3, state: {...}, fsm_history: [...] }
    def run(initial_input:)
      @fsm.reset
      @messages = []
      @plan = nil
      @decision = nil

      loop do
        case @fsm.state_name
        when :INTAKE
          handle_intake(initial_input)
        when :PLAN
          handle_plan
        when :DECIDE
          handle_decide
        when :EXECUTE
          handle_execute
        when :OBSERVE
          handle_observe
        when :LOOP_CHECK
          handle_loop_check
        when :FINALIZE
          return handle_finalize
        when :HALT
          return handle_halt
        end

        break if @fsm.terminal?
      end
    end

    # @!attribute [r] fsm
    #   @return [FSM] The finite state machine instance
    # @!attribute [r] messages
    #   @return [Array<Hash>] Array of message hashes with :role and :content
    # @!attribute [r] plan
    #   @return [Hash, nil] The plan hash with :goal, :required_capabilities, :initial_steps
    # @!attribute [r] decision
    #   @return [Hash, nil] The decision hash with :continue and :reason
    attr_reader :fsm, :messages, :plan, :decision

    private

    # S0: INTAKE - Normalize input, initialize state.
    #
    # Initializes the workflow by creating the initial user message and
    # setting up the state with goal and timestamp.
    #
    # @param input [String] The initial input string
    # @return [void]
    def handle_intake(input)
      @messages = [{ role: "user", content: input }]
      @state.apply!({ goal: input, started_at: Time.now.utc.iso8601 })
      @fsm.transition_to(FSM::STATES[:PLAN], reason: "Input normalized")
    end

    # S1: PLAN - Single-shot planning using /generate.
    #
    # Generates a plan using the planner's plan method. Expects Planner#plan
    # to return a Decision with params containing:
    # - goal: string (required)
    # - required_capabilities: array (optional, defaults to [])
    # - initial_steps: array (optional, defaults to [])
    #
    # @return [void]
    # @raise [ExecutionError] If planner is missing schema or prompt_builder
    def handle_plan
      schema = @planner.instance_variable_get(:@schema)
      prompt_builder = @planner.instance_variable_get(:@prompt_builder)
      raise ExecutionError, "Planner requires schema and prompt_builder for PLAN state" unless schema && prompt_builder

      plan_result = @planner.plan(
        input: @messages.first[:content],
        state: @state.snapshot
      )

      # Extract plan from Decision#params
      # Contract: decision.params must contain :goal (required), :required_capabilities, :initial_steps (optional)
      params = plan_result.params || {}
      goal = params[:goal] || params["goal"] || @messages.first[:content]
      required_capabilities = params[:required_capabilities] || params["required_capabilities"] || []
      initial_steps = params[:initial_steps] || params["initial_steps"] || []

      @plan = {
        goal: goal,
        required_capabilities: required_capabilities,
        initial_steps: initial_steps
      }

      @state.apply!({ plan: @plan })

      @fsm.transition_to(FSM::STATES[:DECIDE], reason: "Plan created")
    rescue StandardError => e
      @fsm.transition_to(FSM::STATES[:HALT], reason: "Plan failed: #{e.message}")
    end

    # S2: DECIDE - Make bounded decision (continue vs stop).
    #
    # Makes a simple decision based on plan validity. If plan exists and has
    # a goal, continues to EXECUTE. Otherwise, halts the workflow.
    #
    # In real implementations, this could use LLM or rule-based logic for
    # more sophisticated decision-making.
    #
    # @return [void]
    def handle_decide
      # Simple decision: if plan exists and is valid, continue to EXECUTE
      # In real implementations, this could use LLM or rule-based logic
      if @plan && @plan[:goal]
        @decision = { continue: true, reason: "Plan valid, proceeding to execution" }
        @fsm.transition_to(FSM::STATES[:EXECUTE], reason: "Decision: continue")
      else
        @decision = { continue: false, reason: "Invalid plan" }
        @fsm.transition_to(FSM::STATES[:HALT], reason: "Invalid plan")
      end
    end

    # S3: EXECUTE - LLM proposes next actions using /chat.
    #
    # This is the ONLY looping state. Uses chat_raw to get full response with
    # tool_calls. If tool calls are present, transitions to OBSERVE. Otherwise,
    # transitions to FINALIZE.
    #
    # @return [void]
    # @raise [ExecutionError] If execution fails
    def handle_execute
      @fsm.increment_iteration

      # Use chat_raw to get full response with tool_calls (ollama-client)
      # chat_raw returns the complete response including tool_calls
      response = @planner.chat_raw(messages: @messages, tools: build_tools_for_chat)

      # Extract tool calls if present
      tool_calls = extract_tool_calls(response)

      if tool_calls.any?
        # Store tool calls for OBSERVE state
        @state.apply!({ pending_tool_calls: tool_calls })
        @fsm.transition_to(FSM::STATES[:OBSERVE], reason: "Tool calls requested")
      else
        # No tool calls, agent is done
        # Extract content from chat_raw response
        content = response.dig(:message,
                               :content) || response.dig("message", "content") || response[:content] || response.to_s
        @messages << { role: "assistant", content: content }
        @fsm.transition_to(FSM::STATES[:FINALIZE], reason: "No tool calls, execution complete")
      end
    rescue StandardError => e
      @fsm.transition_to(FSM::STATES[:HALT], reason: "Execution failed: #{e.message}")
    end

    # S4: OBSERVE - Execute tools, inject real-world results.
    #
    # Executes pending tool calls from the EXECUTE state. Parses tool call
    # arguments (handling JSON strings), calls tools via the registry, and
    # appends results to messages. Handles errors gracefully by including
    # error messages in tool results.
    #
    # @return [void]
    def handle_observe
      tool_calls = @state.snapshot[:pending_tool_calls] || []

      tool_results = []
      parse_error = nil

      tool_calls.each do |tool_call|
        # ollama-client tool_call format: { "function" => { "name" => "...", "arguments" => "..." } }
        function = tool_call[:function] || tool_call["function"] || {}
        action = function[:name] || function["name"] || tool_call[:name] || tool_call["name"]

        # Parse arguments (may be JSON string or hash)
        args_str = function[:arguments] || function["arguments"] ||
                   tool_call[:arguments] || tool_call["arguments"] || "{}"

        begin
          params = args_str.is_a?(String) ? JSON.parse(args_str) : (args_str || {})
        rescue JSON::ParserError => e
          # Malformed JSON in tool call arguments - transition to HALT
          parse_error = e
          break
        end

        begin
          result = @tool_registry.call(action, params)
          tool_results << {
            tool_call_id: tool_call[:id] || tool_call["id"] || SecureRandom.hex(8),
            name: action,
            result: result
          }
        rescue StandardError => e
          tool_results << {
            tool_call_id: tool_call[:id] || tool_call["id"] || SecureRandom.hex(8),
            name: action,
            error: e.message
          }
        end
      end

      if parse_error
        @fsm.transition_to(FSM::STATES[:HALT],
                           reason: "Invalid tool call arguments (JSON parse error): #{parse_error.message}")
        return
      end

      # Append tool results to messages
      tool_results.each do |tool_result|
        @messages << {
          role: "tool",
          content: tool_result.to_json,
          tool_call_id: tool_result[:tool_call_id]
        }
      end

      # Update state with observations
      @state.apply!({
                      observations: (@state.snapshot[:observations] || []) + tool_results,
                      pending_tool_calls: nil
                    })

      @fsm.transition_to(FSM::STATES[:LOOP_CHECK], reason: "Tools executed, #{tool_results.size} results")
    end

    # S5: LOOP_CHECK - Control continuation.
    #
    # Checks guards for continuation: max iterations, policy violations, etc.
    # Uses a simple heuristic: if observations exist, continue to EXECUTE.
    # Otherwise, finalize.
    #
    # @return [void]
    def handle_loop_check
      # Check guards: max iterations, policy violations, etc.
      if @fsm.iteration_count >= @fsm.instance_variable_get(:@max_iterations)
        @fsm.transition_to(FSM::STATES[:HALT], reason: "Max iterations exceeded")
        return
      end

      # Check if we should continue (simple heuristic: if we have observations, continue)
      if @state.snapshot[:observations]&.any?
        @fsm.transition_to(FSM::STATES[:EXECUTE], reason: "Continuing loop")
      else
        @fsm.transition_to(FSM::STATES[:FINALIZE], reason: "No observations, finalizing")
      end
    end

    # S6: FINALIZE - Produce terminal output.
    #
    # Produces the final result hash with completion status, iterations,
    # state snapshot, and FSM history. Records audit log entry.
    #
    # @return [Hash] Final result hash with done: true
    def handle_finalize
      # Optional: call LLM for summary (no tool calls allowed)
      final_message = @messages.last

      result = {
        done: true,
        iterations: @fsm.iteration_count,
        state: @state.snapshot,
        fsm_history: @fsm.history
      }
      result[:final_message] = final_message[:content] if final_message

      @audit_log&.record(
        input: @messages.first[:content],
        decision: @decision,
        result: result
      )

      result
    end

    # S7: HALT - Abort safely.
    #
    # Handles workflow halt due to error. Produces error result hash and
    # records audit log entry, then raises ExecutionError.
    #
    # @return [void]
    # @raise [ExecutionError] Always raises with halt reason
    def handle_halt
      error_reason = @fsm.history.last&.dig(:reason) || "Unknown error"

      result = {
        done: false,
        error: error_reason,
        iterations: @fsm.iteration_count,
        state: @state.snapshot,
        fsm_history: @fsm.history
      }

      @audit_log&.record(
        input: @messages.first&.dig(:content) || "unknown",
        decision: @decision,
        result: result
      )

      raise ExecutionError, "Agent halted: #{error_reason}"
    end

    # Convert ToolRegistry tools to Ollama tool definitions.
    #
    # Returns array of tool definitions in Ollama format. This is a basic
    # implementation that creates minimal tool schemas. Override this method
    # to provide proper JSON schemas for each tool.
    #
    # @return [Array<Hash>] Array of tool definition hashes in Ollama format
    #
    # @example Override to provide custom schemas
    #   def build_tools_for_chat
    #     [
    #       {
    #         type: "function",
    #         function: {
    #           name: "search",
    #           description: "Search the web",
    #           parameters: {
    #             type: "object",
    #             properties: {
    #               query: { type: "string", description: "Search query" }
    #             },
    #             required: ["query"]
    #           }
    #         }
    #       }
    #     ]
    #   end
    def build_tools_for_chat
      tools_hash = @tool_registry.instance_variable_get(:@tools) || {}
      return [] if tools_hash.empty?

      # Basic tool definition format for Ollama
      # Users should override this method to provide proper JSON schemas for each tool
      tools_hash.keys.map do |tool_name|
        {
          type: "function",
          function: {
            name: tool_name.to_s,
            description: "Tool: #{tool_name}",
            parameters: {
              type: "object",
              properties: {},
              additionalProperties: true
            }
          }
        }
      end
    end

    # Extract tool calls from ollama-client chat_raw() response.
    #
    # Handles various response formats and extracts tool_calls array.
    # Supports both symbol and string keys, and checks multiple possible
    # locations in the response hash.
    #
    # @param response [Hash, Object] The chat_raw response (may be hash or object with tool_calls method)
    # @return [Array] Array of tool call hashes, empty array if none found
    def extract_tool_calls(response)
      if response.is_a?(Hash)
        # ollama-client chat_raw returns tool_calls in message.tool_calls
        tool_calls = response.dig(:message, :tool_calls) || response.dig("message", "tool_calls")
        return tool_calls if tool_calls.is_a?(Array) && !tool_calls.empty?

        # Fallback: check other possible locations
        response[:tool_calls] || response["tool_calls"] || []
      elsif response.respond_to?(:tool_calls)
        response.tool_calls
      else
        []
      end
    end
  end
end
