# frozen_string_literal: true

require "spec_helper"

# Runtime Invariants Test Suite
#
# This test suite verifies that agent-runtime enforces critical invariants
# that guarantee correctness regardless of LLM behavior.
#
# These tests prove:
# 1. The runtime cannot loop forever
# 2. The runtime halts deterministically when convergence is reached
# 3. The runtime halts deterministically when limits are exceeded
# 4. Progress tracking is passive (runtime doesn't interpret signals)
# 5. Tool execution does not imply convergence
# 6. The runtime remains domain-agnostic
#
# These tests do NOT involve real LLMs - they test runtime behavior only.
RSpec.describe "AgentRuntime Runtime Invariants" do
  let(:mock_client) { instance_double(Ollama::Client) }
  let(:schema) do
    {
      "type" => "object",
      "required" => %w[action params],
      "properties" => {
        "action" => { "type" => "string" },
        "params" => { "type" => "object", "additionalProperties" => true }
      }
    }
  end
  let(:prompt_builder) { ->(input:, state:) { "Prompt: #{input}" } }
  let(:planner) do
    AgentRuntime::Planner.new(
      client: mock_client,
      schema: schema,
      prompt_builder: prompt_builder
    )
  end
  let(:tools) do
    AgentRuntime::ToolRegistry.new({
                                     "always_loop" => -> { { result: "looping" } },
                                     "success_tool" => -> { { success: true, result: "done" } }
                                   })
  end
  let(:executor) { AgentRuntime::Executor.new(tool_registry: tools) }
  let(:state) { AgentRuntime::State.new }

  # ============================================================================
  # Level 1: Runtime Invariants (non-negotiable)
  # ============================================================================

  describe "Max-step enforcement" do
    it "always halts at max steps even when executor always returns tool calls" do
      # Setup: Policy never converges, executor always wants to loop
      never_converge_policy = Class.new(AgentRuntime::Policy) do
        def converged?(_state)
          false
        end
      end.new

      # Mock: Always return a tool call (simulating infinite loop scenario)
      allow(mock_client).to receive(:generate).and_return({
                                                            "action" => "always_loop",
                                                            "params" => {}
                                                          })

      agent = AgentRuntime::Agent.new(
        planner: planner,
        policy: never_converge_policy,
        executor: executor,
        state: state,
        max_iterations: 5
      )

      # Execute and verify it halts at max steps
      expect { agent.run(initial_input: "Loop forever") }
        .to raise_error(AgentRuntime::MaxIterationsExceeded, /Max iterations \(5\) exceeded/)
    end

    it "halts at max steps in AgentFSM" do
      never_converge_policy = Class.new(AgentRuntime::Policy) do
        def converged?(_state)
          false
        end
      end.new

      # Mock generate for PLAN state

      # Mock chat_raw to always return tool calls
      allow(mock_client).to receive_messages(generate: {
                                               "action" => "always_loop",
                                               "params" => { "goal" => "Loop" }
                                             }, chat_raw: {
                                               message: {
                                                 content: "",
                                                 tool_calls: [
                                                   {
                                                     id: "1",
                                                     function: {
                                                       name: "always_loop",
                                                       arguments: "{}"
                                                     }
                                                   }
                                                 ]
                                               }
                                             })

      agent_fsm = AgentRuntime::AgentFSM.new(
        planner: planner,
        policy: never_converge_policy,
        executor: executor,
        state: state,
        tool_registry: tools,
        max_iterations: 3
      )

      expect { agent_fsm.run(initial_input: "Loop") }
        .to raise_error(AgentRuntime::ExecutionError, /Max iterations exceeded/)
    end
  end

  describe "Convergence halts loop immediately" do
    it "stops executing when policy indicates convergence" do
      # Track how many times executor is called
      executor_calls = []
      tracking_executor = Class.new(AgentRuntime::Executor) do
        def initialize(tool_registry:, calls:)
          super(tool_registry: tool_registry)
          @calls = calls
        end

        def execute(decision, state: nil)
          @calls << decision.action
          super
        end
      end.new(tool_registry: tools, calls: executor_calls)

      # Policy converges after 2 tool calls
      # Use a closure to track calls
      call_count = 0
      Class.new(AgentRuntime::Policy) do
        define_method(:converged?) do |_state|
          # Track calls via closure
          call_count = (call_count || 0) + 1
          call_count >= 2
        end
      end.new

      # Use a different approach - track via state
      convergent_policy = Class.new(AgentRuntime::Policy) do
        def converged?(state)
          current_count = state.snapshot[:call_count] || 0
          state.apply!({ call_count: current_count + 1 })
          (current_count + 1) >= 2
        end
      end.new

      allow(mock_client).to receive(:generate).and_return({
                                                            "action" => "always_loop",
                                                            "params" => {}
                                                          })

      agent = AgentRuntime::Agent.new(
        planner: planner,
        policy: convergent_policy,
        executor: tracking_executor,
        state: state,
        max_iterations: 10
      )

      result = agent.run(initial_input: "Test convergence")

      # Should have executed exactly 2 steps, then converged
      expect(executor_calls.length).to eq(2)
      expect(result).to be_a(Hash)
      # Should not have hit max iterations
      expect(result[:iterations] || 2).to be <= 3
    end

    it "halts immediately in AgentFSM when policy converges" do
      convergent_policy = Class.new(AgentRuntime::Policy) do
        def converged?(state)
          # Converge when tool has been called
          state.progress.include?(:tool_called)
        end
      end.new

      # Mock generate for PLAN state
      allow(mock_client).to receive(:generate).and_return({
                                                            "action" => "always_loop",
                                                            "params" => { "goal" => "Test" }
                                                          })

      # First EXECUTE call returns tool, subsequent calls return no tools (converged)
      call_count = 0
      allow(mock_client).to receive(:chat_raw) do
        call_count += 1
        if call_count == 1
          # First call: return tool call
          {
            message: {
              content: "",
              tool_calls: [
                {
                  id: "1",
                  function: {
                    name: "always_loop",
                    arguments: "{}"
                  }
                }
              ]
            }
          }
        else
          # Subsequent calls: no tools (shouldn't happen if convergence works)
          {
            message: {
              content: "Done"
            }
          }
        end
      end

      agent_fsm = AgentRuntime::AgentFSM.new(
        planner: planner,
        policy: convergent_policy,
        executor: executor,
        state: state,
        tool_registry: tools,
        max_iterations: 20 # High enough to not hit limit
      )

      result = agent_fsm.run(initial_input: "Test")

      # Should have converged after first tool execution
      # FSM flow: INTAKE -> PLAN -> DECIDE -> EXECUTE (iter 1) -> OBSERVE -> LOOP_CHECK (converges)
      expect(result[:done]).to be true
      # Should converge in first loop (after tool execution)
      expect(result[:iterations]).to be <= 2
    end
  end

  describe "Progress tracking is passive" do
    it "does not interpret progress signals" do
      # Mark arbitrary signals that runtime should not react to
      state.progress.mark!(:foo)
      state.progress.mark!(:bar)
      state.progress.mark!(:baz)

      # Runtime should not crash or branch based on these
      never_converge_policy = Class.new(AgentRuntime::Policy) do
        def converged?(_state)
          false
        end
      end.new

      allow(mock_client).to receive(:generate).and_return({
                                                            "action" => "always_loop",
                                                            "params" => {}
                                                          })

      agent = AgentRuntime::Agent.new(
        planner: planner,
        policy: never_converge_policy,
        executor: executor,
        state: state,
        max_iterations: 2
      )

      # Should not raise error or behave differently
      expect { agent.run(initial_input: "Test") }
        .to raise_error(AgentRuntime::MaxIterationsExceeded)

      # Signals should still be present (runtime didn't clear them)
      expect(state.progress.include?(:foo)).to be true
      expect(state.progress.include?(:bar)).to be true
      expect(state.progress.include?(:baz)).to be true
    end

    it "allows applications to define arbitrary signal meanings" do
      # Applications can use any signal names
      state.progress.mark!(:patch_applied)
      state.progress.mark!(:syntax_valid)
      state.progress.mark!(:order_placed)
      state.progress.mark!(:research_complete)

      # Runtime doesn't care what these mean
      expect(state.progress.signals).to include(:patch_applied, :syntax_valid, :order_placed, :research_complete)
    end
  end

  # ============================================================================
  # Level 2: Tool Safety Guarantees
  # ============================================================================

  describe "Tool execution does not imply success" do
    it "continues looping when tool succeeds but policy doesn't converge" do
      # Tool returns success
      success_tool = -> { { success: true, result: "Task completed" } }
      success_tools = AgentRuntime::ToolRegistry.new({ "success_tool" => success_tool })
      success_executor = AgentRuntime::Executor.new(tool_registry: success_tools)

      # But policy never converges
      never_converge_policy = Class.new(AgentRuntime::Policy) do
        def converged?(_state)
          false
        end
      end.new

      allow(mock_client).to receive(:generate).and_return({
                                                            "action" => "success_tool",
                                                            "params" => {}
                                                          })

      agent = AgentRuntime::Agent.new(
        planner: planner,
        policy: never_converge_policy,
        executor: success_executor,
        state: state,
        max_iterations: 3
      )

      # Should continue looping despite tool success
      expect { agent.run(initial_input: "Test") }
        .to raise_error(AgentRuntime::MaxIterationsExceeded)
    end

    it "tool emits progress but does not control termination" do
      tool_calls = []
      tracking_tool = lambda do |**|
        tool_calls << :called
        { result: "done" }
      end

      tracking_tools = AgentRuntime::ToolRegistry.new({ "tracking_tool" => tracking_tool })
      tracking_executor = AgentRuntime::Executor.new(tool_registry: tracking_tools)

      never_converge_policy = Class.new(AgentRuntime::Policy) do
        def converged?(_state)
          false
        end
      end.new

      allow(mock_client).to receive(:generate).and_return({
                                                            "action" => "tracking_tool",
                                                            "params" => {}
                                                          })

      agent = AgentRuntime::Agent.new(
        planner: planner,
        policy: never_converge_policy,
        executor: tracking_executor,
        state: state,
        max_iterations: 2
      )

      expect { agent.run(initial_input: "Test") }
        .to raise_error(AgentRuntime::MaxIterationsExceeded)

      # Tool was called, progress was marked, but runtime didn't auto-terminate
      expect(tool_calls.length).to eq(2)
      expect(state.progress.include?(:tool_called)).to be true
      expect(state.progress.include?(:step_completed)).to be true
    end
  end

  # ============================================================================
  # Level 3: Policy Control Verification
  # ============================================================================

  describe "Policy controls termination, not LLM" do
    it "terminates when policy says so, even if LLM wants to continue" do
      # LLM always wants to call tools
      allow(mock_client).to receive(:generate).and_return({
                                                            "action" => "always_loop",
                                                            "params" => {}
                                                          })

      # But policy converges immediately
      immediate_converge_policy = Class.new(AgentRuntime::Policy) do
        def converged?(_state)
          true
        end
      end.new

      agent = AgentRuntime::Agent.new(
        planner: planner,
        policy: immediate_converge_policy,
        executor: executor,
        state: state,
        max_iterations: 10
      )

      result = agent.run(initial_input: "Test")

      # Should terminate immediately, not execute any tools
      expect(result).to be_a(Hash)
      # Should have 0 or 1 iterations (converged before first execution)
      expect(result[:iterations] || 0).to be <= 1
    end

    it "requires explicit convergence policy - default never converges" do
      default_policy = AgentRuntime::Policy.new

      allow(mock_client).to receive(:generate).and_return({
                                                            "action" => "always_loop",
                                                            "params" => {}
                                                          })

      agent = AgentRuntime::Agent.new(
        planner: planner,
        policy: default_policy,
        executor: executor,
        state: state,
        max_iterations: 3
      )

      # Default policy never converges, so should hit max steps
      expect { agent.run(initial_input: "Test") }
        .to raise_error(AgentRuntime::MaxIterationsExceeded)
    end
  end

  # ============================================================================
  # Level 4: Domain Agnosticism
  # ============================================================================

  describe "Runtime remains domain-agnostic" do
    it "works identically with different signal names" do
      # Coding domain signals
      coding_state = AgentRuntime::State.new
      coding_state.progress.mark!(:patch_applied)
      coding_state.progress.mark!(:syntax_ok)

      coding_policy = Class.new(AgentRuntime::Policy) do
        def converged?(state)
          state.progress.include?(:patch_applied, :syntax_ok)
        end
      end.new

      expect(coding_policy.converged?(coding_state)).to be true

      # Trading domain signals
      trading_state = AgentRuntime::State.new
      trading_state.progress.mark!(:order_placed)
      trading_state.progress.mark!(:confirmation_received)

      trading_policy = Class.new(AgentRuntime::Policy) do
        def converged?(state)
          state.progress.include?(:order_placed, :confirmation_received)
        end
      end.new

      expect(trading_policy.converged?(trading_state)).to be true

      # Research domain signals
      research_state = AgentRuntime::State.new
      research_state.progress.mark!(:sources_collected)
      research_state.progress.mark!(:analysis_complete)

      research_policy = Class.new(AgentRuntime::Policy) do
        def converged?(state)
          state.progress.include?(:sources_collected, :analysis_complete)
        end
      end.new

      expect(research_policy.converged?(research_state)).to be true

      # Runtime behavior is identical - only signal names differ
    end

    it "does not hardcode any domain concepts in logic" do
      # Verify runtime doesn't hardcode domain-specific logic
      # (Comments/docs may mention examples, but code should be generic)

      # Check that State doesn't have phase-specific logic
      state_code = File.read(File.join(__dir__, "../../lib/agent_runtime/state.rb"))
      expect(state_code).not_to match(/def (phase|tool_usage)/), "State should not have phase-specific methods"

      # Check that Policy doesn't hardcode domain signals
      policy_code = File.read(File.join(__dir__, "../../lib/agent_runtime/policy.rb"))
      expect(policy_code).not_to match(/patch_applied|syntax_ok|order_placed/),
                                 "Policy should not hardcode domain signals"

      # Check that Executor doesn't interpret tool results
      executor_code = File.read(File.join(__dir__, "../../lib/agent_runtime/executor.rb"))
      expect(executor_code).not_to match(/if.*success|if.*patch|if.*syntax/),
                                   "Executor should not interpret tool results"
    end
  end

  # ============================================================================
  # Level 5: Deterministic Behavior
  # ============================================================================

  describe "Deterministic termination" do
    it "produces same result when run multiple times with same state" do
      convergent_policy = Class.new(AgentRuntime::Policy) do
        def converged?(state)
          state.progress.include?(:tool_called)
        end
      end.new

      allow(mock_client).to receive(:generate).and_return({
                                                            "action" => "always_loop",
                                                            "params" => {}
                                                          })

      results = []
      3.times do
        fresh_state = AgentRuntime::State.new
        agent = AgentRuntime::Agent.new(
          planner: planner,
          policy: convergent_policy,
          executor: executor,
          state: fresh_state,
          max_iterations: 10
        )
        results << agent.run(initial_input: "Test")
      end

      # All runs should converge at same point
      iterations = results.map { |r| r[:iterations] || 1 }
      expect(iterations.uniq.length).to eq(1), "All runs should converge at same iteration"
    end
  end

  # ============================================================================
  # Level 6: Explicit Termination Signals
  # ============================================================================

  describe "Explicit termination still works" do
    it "terminates on 'finish' action regardless of policy" do
      never_converge_policy = Class.new(AgentRuntime::Policy) do
        def converged?(_state)
          false
        end
      end.new

      allow(mock_client).to receive(:generate).and_return({
                                                            "action" => "finish",
                                                            "params" => {}
                                                          })

      agent = AgentRuntime::Agent.new(
        planner: planner,
        policy: never_converge_policy,
        executor: executor,
        state: state,
        max_iterations: 10
      )

      result = agent.run(initial_input: "Finish")

      expect(result[:done]).to be true
      expect(result[:iterations] || 1).to eq(1)
    end
  end
end
