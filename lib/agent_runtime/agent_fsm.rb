# frozen_string_literal: true

require "json"
require "securerandom"

module AgentRuntime
  # Agentic workflow implementation using formal FSM
  # Maps directly to the canonical agentic workflow specification
  class AgentFSM
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

    # Run the complete agentic workflow from INTAKE to FINALIZE/HALT
    def run(initial_input:)
      @fsm.reset
      @messages = []
      @plan = nil
      @decision = nil

      loop do
        break if @fsm.terminal?

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
      end
    end

    attr_reader :fsm, :messages, :plan, :decision

    private

    # S0: INTAKE - Normalize input, initialize state
    def handle_intake(input)
      @messages = [{ role: "user", content: input }]
      @state.apply!({ goal: input, started_at: Time.now.utc.iso8601 })
      @fsm.transition_to(FSM::STATES[:PLAN], reason: "Input normalized")
    end

    # S1: PLAN - Single-shot planning using /generate
    def handle_plan
      schema = @planner.instance_variable_get(:@schema)
      prompt_builder = @planner.instance_variable_get(:@prompt_builder)
      raise ExecutionError, "Planner requires schema and prompt_builder for PLAN state" unless schema && prompt_builder

      plan_result = @planner.plan(
        input: @messages.first[:content],
        state: @state.snapshot
      )

      @plan = {
        goal: plan_result.params&.dig(:goal) || @messages.first[:content],
        required_capabilities: plan_result.params&.dig(:required_capabilities) || [],
        initial_steps: plan_result.params&.dig(:initial_steps) || []
      }

      @state.apply!({ plan: @plan })

      @fsm.transition_to(FSM::STATES[:DECIDE], reason: "Plan created")
    rescue StandardError => e
      @fsm.transition_to(FSM::STATES[:HALT], reason: "Plan failed: #{e.message}")
    end

    # S2: DECIDE - Make bounded decision (continue vs stop)
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

    # S3: EXECUTE - LLM proposes next actions using /chat
    # This is the ONLY looping state
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

    # S4: OBSERVE - Execute tools, inject real-world results
    def handle_observe
      tool_calls = @state.snapshot[:pending_tool_calls] || []

      tool_results = tool_calls.map do |tool_call|
        # ollama-client tool_call format: { "function" => { "name" => "...", "arguments" => "..." } }
        function = tool_call[:function] || tool_call["function"] || {}
        action = function[:name] || function["name"] || tool_call[:name] || tool_call["name"]

        # Parse arguments (may be JSON string or hash)
        args_str = function[:arguments] || function["arguments"] || tool_call[:arguments] || tool_call["arguments"] || "{}"
        params = args_str.is_a?(String) ? JSON.parse(args_str) : (args_str || {})

        begin
          result = @tool_registry.call(action, params)
          {
            tool_call_id: tool_call[:id] || tool_call["id"] || SecureRandom.hex(8),
            name: action,
            result: result
          }
        rescue StandardError => e
          {
            tool_call_id: tool_call[:id] || tool_call["id"] || SecureRandom.hex(8),
            name: action,
            error: e.message
          }
        end
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

    # S5: LOOP_CHECK - Control continuation
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

    # S6: FINALIZE - Produce terminal output
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

    # S7: HALT - Abort safely
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

    def build_tools_for_chat
      # Convert tool_registry tools to ollama-client Tool format
      # ollama-client expects Ollama::Tool objects or array of Tool objects
      # For now, return nil - tools can be passed directly if needed
      # In production, you'd convert your ToolRegistry to Ollama::Tool objects
      # Example:
      #   tools = @tool_registry.instance_variable_get(:@tools)
      #   tools.map { |name, callable| build_ollama_tool(name, callable) }
      nil
    end

    def extract_tool_calls(response)
      # Extract tool calls from ollama-client chat_raw() response
      # chat_raw returns: { "message" => { "tool_calls" => [...] } }
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
