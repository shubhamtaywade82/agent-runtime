# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe AgentRuntime::Agent do
  let(:mock_planner) { instance_double(AgentRuntime::Planner) }
  let(:mock_policy) { instance_double(AgentRuntime::Policy) }
  let(:mock_executor) { instance_double(AgentRuntime::Executor) }
  let(:state) { AgentRuntime::State.new }
  let(:audit_log) { instance_double(AgentRuntime::AuditLog) }

  let(:agent) do
    described_class.new(
      planner: mock_planner,
      policy: mock_policy,
      executor: mock_executor,
      state: state,
      audit_log: audit_log,
      max_iterations: 10
    )
  end

  describe "#initialize" do
    it "initializes with all required components" do
      agent = described_class.new(
        planner: mock_planner,
        policy: mock_policy,
        executor: mock_executor,
        state: state
      )
      expect(agent).to be_a(described_class)
    end

    it "initializes with default max_iterations" do
      agent = described_class.new(
        planner: mock_planner,
        policy: mock_policy,
        executor: mock_executor,
        state: state
      )
      expect(agent.instance_variable_get(:@max_iterations)).to eq(50)
    end

    it "initializes with custom max_iterations" do
      agent = described_class.new(
        planner: mock_planner,
        policy: mock_policy,
        executor: mock_executor,
        state: state,
        max_iterations: 100
      )
      expect(agent.instance_variable_get(:@max_iterations)).to eq(100)
    end

    it "initializes without audit_log" do
      agent = described_class.new(
        planner: mock_planner,
        policy: mock_policy,
        executor: mock_executor,
        state: state
      )
      expect(agent.instance_variable_get(:@audit_log)).to be_nil
    end
  end

  describe "#step" do
    it "executes a single step" do
      decision = AgentRuntime::Decision.new(action: "fetch", params: {})
      result = { data: "result" }

      allow(mock_planner).to receive(:plan).and_return(decision)
      allow(mock_policy).to receive(:validate!)
      allow(mock_executor).to receive(:execute).and_return(result)
      allow(audit_log).to receive(:record)
      allow(state).to receive(:snapshot).and_return({})
      allow(state).to receive(:apply!)

      agent.step(input: "test input")

      expect(mock_planner).to have_received(:plan).with(input: "test input", state: {})
      expect(mock_policy).to have_received(:validate!).with(decision, state: state)
      expect(mock_executor).to have_received(:execute).with(decision, state: state)
      expect(state).to have_received(:apply!).with(result)
      expect(audit_log).to have_received(:record).with(
        input: "test input",
        decision: decision,
        result: result
      )
    end

    it "returns execution result" do
      decision = AgentRuntime::Decision.new(action: "fetch", params: {})
      result = { data: "result" }

      allow(mock_planner).to receive(:plan).and_return(decision)
      allow(mock_policy).to receive(:validate!)
      allow(mock_executor).to receive(:execute).and_return(result)
      allow(audit_log).to receive(:record)
      allow(state).to receive(:snapshot).and_return({})
      allow(state).to receive(:apply!)

      expect(agent.step(input: "test")).to eq(result)
    end

    it "raises PolicyViolation when policy validation fails" do
      decision = AgentRuntime::Decision.new(action: "fetch", params: {})
      allow(mock_planner).to receive(:plan).and_return(decision)
      allow(mock_policy).to receive(:validate!)
        .and_raise(AgentRuntime::PolicyViolation, "Invalid")

      allow(state).to receive(:snapshot).and_return({})

      expect { agent.step(input: "test") }
        .to raise_error(AgentRuntime::PolicyViolation, /Invalid/)
    end

    it "raises ExecutionError when execution fails" do
      decision = AgentRuntime::Decision.new(action: "fetch", params: {})
      allow(mock_planner).to receive(:plan).and_return(decision)
      allow(mock_policy).to receive(:validate!)
      allow(mock_executor).to receive(:execute)
        .and_raise(AgentRuntime::ExecutionError, "Execution failed")

      allow(state).to receive(:snapshot).and_return({})

      expect { agent.step(input: "test") }
        .to raise_error(AgentRuntime::ExecutionError, /Execution failed/)
    end

    it "works without audit_log" do
      agent_no_log = described_class.new(
        planner: mock_planner,
        policy: mock_policy,
        executor: mock_executor,
        state: state
      )

      decision = AgentRuntime::Decision.new(action: "fetch", params: {})
      result = { data: "result" }

      allow(mock_planner).to receive(:plan).and_return(decision)
      allow(mock_policy).to receive(:validate!)
      allow(mock_executor).to receive(:execute).and_return(result)
      allow(state).to receive(:snapshot).and_return({})
      allow(state).to receive(:apply!)

      expect { agent_no_log.step(input: "test") }.not_to raise_error
    end
  end

  describe "#run" do
    it "runs until finish action and returns final result" do
      finish_decision = AgentRuntime::Decision.new(action: "finish")
      allow(mock_planner).to receive(:plan).and_return(finish_decision)
      allow(mock_policy).to receive(:validate!)
      allow(mock_executor).to receive(:execute).and_return({ done: true })
      allow(audit_log).to receive(:record)
      allow(state).to receive(:snapshot).and_return({})
      allow(state).to receive(:apply!)

      result = agent.run(initial_input: "test")

      expect(result[:done]).to be true
    end

    it "runs until done result" do
      decision = AgentRuntime::Decision.new(action: "fetch", params: {})
      allow(mock_planner).to receive(:plan).and_return(decision)
      allow(mock_policy).to receive(:validate!)
      allow(mock_executor).to receive(:execute).and_return({ done: true })
      allow(audit_log).to receive(:record)
      allow(state).to receive(:snapshot).and_return({})
      allow(state).to receive(:apply!)

      result = agent.run(initial_input: "test")

      expect(result[:done]).to be true
    end

    it "raises MaxIterationsExceeded when max iterations exceeded" do
      decision = AgentRuntime::Decision.new(action: "fetch", params: {})
      allow(mock_planner).to receive(:plan).and_return(decision)
      allow(mock_policy).to receive(:validate!)
      allow(mock_executor).to receive(:execute).and_return({})
      allow(audit_log).to receive(:record)
      allow(state).to receive(:snapshot).and_return({})
      allow(state).to receive(:apply!)

      expect { agent.run(initial_input: "test") }
        .to raise_error(AgentRuntime::MaxIterationsExceeded, /Max iterations/)
    end

    it "uses custom input_builder when provided" do
      finish_decision = AgentRuntime::Decision.new(action: "finish")
      input_builder = ->(result, iteration) { "Input #{iteration}: #{result.inspect}" }

      allow(mock_planner).to receive(:plan).and_return(finish_decision)
      allow(mock_policy).to receive(:validate!)
      allow(mock_executor).to receive(:execute).and_return({ done: true })
      allow(audit_log).to receive(:record)
      allow(state).to receive(:snapshot).and_return({})
      allow(state).to receive(:apply!)

      agent.run(initial_input: "test", input_builder: input_builder)

      expect(mock_planner).to have_received(:plan).with(input: "test", state: {})
    end

    it "handles multiple iterations before termination" do
      continue_decision = AgentRuntime::Decision.new(action: "continue", params: {})
      finish_decision = AgentRuntime::Decision.new(action: "finish")

      allow(mock_planner).to receive(:plan)
        .and_return(continue_decision, continue_decision, finish_decision)
      allow(mock_policy).to receive(:validate!)
      allow(mock_executor).to receive(:execute)
        .and_return({ step: 1 }, { step: 2 }, { done: true })
      allow(audit_log).to receive(:record)
      allow(state).to receive(:snapshot).and_return({})
      allow(state).to receive(:apply!)

      result = agent.run(initial_input: "test")

      expect(result[:done]).to be true
    end
  end

  describe "when handling edge cases" do
    it "handles empty input" do
      decision = AgentRuntime::Decision.new(action: "finish")
      allow(mock_planner).to receive(:plan).and_return(decision)
      allow(mock_policy).to receive(:validate!)
      allow(mock_executor).to receive(:execute).and_return({ done: true })
      allow(audit_log).to receive(:record)
      allow(state).to receive(:snapshot).and_return({})
      allow(state).to receive(:apply!)

      result = agent.step(input: "")
      expect(result).to eq({ done: true })
    end

    it "handles nil input" do
      decision = AgentRuntime::Decision.new(action: "finish")
      allow(mock_planner).to receive(:plan).and_return(decision)
      allow(mock_policy).to receive(:validate!)
      allow(mock_executor).to receive(:execute).and_return({ done: true })
      allow(audit_log).to receive(:record)
      allow(state).to receive(:snapshot).and_return({})
      allow(state).to receive(:apply!)

      result = agent.step(input: nil)
      expect(result).to eq({ done: true })
    end

    it "handles max_iterations of 1" do
      agent_one = described_class.new(
        planner: mock_planner,
        policy: mock_policy,
        executor: mock_executor,
        state: state,
        max_iterations: 1
      )

      decision = AgentRuntime::Decision.new(action: "continue", params: {})
      allow(mock_planner).to receive(:plan).and_return(decision)
      allow(mock_policy).to receive(:validate!)
      allow(mock_executor).to receive(:execute).and_return({})
      allow(audit_log).to receive(:record)
      allow(state).to receive(:snapshot).and_return({})
      allow(state).to receive(:apply!)

      expect { agent_one.run(initial_input: "test") }
        .to raise_error(AgentRuntime::MaxIterationsExceeded)
    end

    it "handles very large max_iterations" do
      agent_large = described_class.new(
        planner: mock_planner,
        policy: mock_policy,
        executor: mock_executor,
        state: state,
        max_iterations: 1_000_000
      )

      finish_decision = AgentRuntime::Decision.new(action: "finish")
      allow(mock_planner).to receive(:plan).and_return(finish_decision)
      allow(mock_policy).to receive(:validate!)
      allow(mock_executor).to receive(:execute).and_return({ done: true })
      allow(audit_log).to receive(:record)
      allow(state).to receive(:snapshot).and_return({})
      allow(state).to receive(:apply!)

      result = agent_large.run(initial_input: "test")
      expect(result[:done]).to be true
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
