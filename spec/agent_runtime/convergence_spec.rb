# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe "AgentRuntime Convergence" do
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
  let(:prompt_builder) { ->(input:, state:) { "Prompt" } }
  let(:planner) do
    AgentRuntime::Planner.new(
      client: mock_client,
      schema: schema,
      prompt_builder: prompt_builder
    )
  end
  let(:tools) do
    AgentRuntime::ToolRegistry.new({
                                     "search" => ->(query:) { { result: "Found: #{query}" } }
                                   })
  end
  let(:executor) { AgentRuntime::Executor.new(tool_registry: tools) }
  let(:state) { AgentRuntime::State.new }

  describe "Policy#converged?" do
    it "returns false by default (never converges)" do
      policy = AgentRuntime::Policy.new
      expect(policy.converged?(state)).to be false
    end

    it "can be overridden by subclasses" do
      convergent_policy = Class.new(AgentRuntime::Policy) do
        def converged?(state)
          state.progress.include?(:goal_achieved)
        end
      end.new

      expect(convergent_policy.converged?(state)).to be false

      state.progress.mark!(:goal_achieved)
      expect(convergent_policy.converged?(state)).to be true
    end

    it "allows complex convergence logic" do
      complex_policy = Class.new(AgentRuntime::Policy) do
        def converged?(state)
          state.progress.include?(:primary_task_done, :validation_complete)
        end
      end.new

      expect(complex_policy.converged?(state)).to be false

      state.progress.mark!(:primary_task_done)
      expect(complex_policy.converged?(state)).to be false

      state.progress.mark!(:validation_complete)
      expect(complex_policy.converged?(state)).to be true
    end
  end

  describe "Agent#run with convergence" do
    it "halts when policy indicates convergence" do
      # Create a policy that converges after tool is called
      convergent_policy = Class.new(AgentRuntime::Policy) do
        def converged?(state)
          # Converge when tool has been called (simulating work completion)
          state.progress.include?(:tool_called)
        end
      end.new

      llm_response = {
        "action" => "search",
        "params" => { "query" => "test" }
      }

      allow(mock_client).to receive(:generate).and_return(llm_response)

      agent = AgentRuntime::Agent.new(
        planner: planner,
        policy: convergent_policy,
        executor: executor,
        state: state,
        max_iterations: 10
      )

      result = agent.run(initial_input: "Search for test")

      # Should have executed one step, marked progress, then converged
      expect(state.progress.include?(:tool_called)).to be true
      expect(state.progress.include?(:step_completed)).to be true
      expect(result).to be_a(Hash)
      # Should have converged after first iteration, not hit max
      expect(result[:iterations] || 1).to be <= 2
    end

    it "still halts on max iterations even with convergence policy" do
      convergent_policy = Class.new(AgentRuntime::Policy) do
        def converged?(_state)
          false # Never converges
        end
      end.new

      llm_response = {
        "action" => "search",
        "params" => { "query" => "test" }
      }

      allow(mock_client).to receive(:generate).and_return(llm_response)

      agent = AgentRuntime::Agent.new(
        planner: planner,
        policy: convergent_policy,
        executor: executor,
        state: AgentRuntime::State.new, # Fresh state
        max_iterations: 2
      )

      expect { agent.run(initial_input: "Search") }
        .to raise_error(AgentRuntime::MaxIterationsExceeded)
    end

    it "still halts on finish action even with convergence policy" do
      convergent_policy = Class.new(AgentRuntime::Policy) do
        def converged?(_state)
          false # Never converges
        end
      end.new

      llm_response = {
        "action" => "finish",
        "params" => {}
      }

      allow(mock_client).to receive(:generate).and_return(llm_response)

      agent = AgentRuntime::Agent.new(
        planner: planner,
        policy: convergent_policy,
        executor: executor,
        state: state,
        max_iterations: 10
      )

      result = agent.run(initial_input: "Finish")
      expect(result[:done]).to be true
    end
  end

  describe "Executor progress signal emission" do
    it "marks progress signals when tool is executed" do
      decision = AgentRuntime::Decision.new(
        action: "search",
        params: { query: "test" }
      )

      executor.execute(decision, state: state)

      expect(state.progress.include?(:tool_called)).to be true
      expect(state.progress.include?(:step_completed)).to be true
    end

    it "does not mark signals for finish action" do
      decision = AgentRuntime::Decision.new(action: "finish")

      executor.execute(decision, state: state)

      expect(state.progress.include?(:tool_called)).to be false
    end

    it "handles non-State state gracefully" do
      decision = AgentRuntime::Decision.new(
        action: "search",
        params: { query: "test" }
      )

      # Should not raise error when state is not a State instance
      expect { executor.execute(decision, state: {}) }.not_to raise_error
    end
  end

  describe "State progress integration" do
    it "provides progress tracker on state" do
      expect(state.progress).to be_a(AgentRuntime::ProgressTracker)
    end

    it "allows marking signals on state progress" do
      state.progress.mark!(:custom_signal)
      expect(state.progress.include?(:custom_signal)).to be true
    end

    it "progress tracker persists across state updates" do
      state.progress.mark!(:signal_a)
      state.apply!({ new_key: "value" })
      expect(state.progress.include?(:signal_a)).to be true
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
