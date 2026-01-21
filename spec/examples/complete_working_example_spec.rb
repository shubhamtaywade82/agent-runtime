# frozen_string_literal: true

require "spec_helper"
require "json"

# rubocop:disable RSpec/MultipleMemoizedHelpers, RSpec/DescribeClass
RSpec.describe "Complete Working Example Usage", type: :integration do
  # This spec tests the usage pattern demonstrated in examples/complete_working_example.rb
  # It verifies that the basic Agent and AgentFSM usage patterns work correctly.

  let(:mock_client) { instance_double(Ollama::Client) }

  let(:schema) do
    {
      "type" => "object",
      "required" => %w[action params],
      "properties" => {
        "action" => {
          "type" => "string",
          "enum" => %w[search calculate get_time finish],
          "description" => "The action to execute"
        },
        "params" => {
          "type" => "object",
          "additionalProperties" => true,
          "description" => "Parameters for the action"
        },
        "confidence" => {
          "type" => "number",
          "minimum" => 0,
          "maximum" => 1,
          "description" => "Confidence level (0.0 to 1.0)"
        }
      }
    }
  end

  let(:prompt_builder) do
    lambda do |input:, state:|
      <<~PROMPT
        You are a helpful assistant that decides what actions to take.

        User Request: #{input}
        Current State: #{state.to_json}

        Available Actions:
        - search: Search for information (requires: query)
        - calculate: Perform calculations (requires: expression like "2+2" or "10*5")
        - get_time: Get current time (no parameters needed)
        - finish: Complete the task

        Respond with a JSON object:
        {
          "action": "one of the available actions",
          "params": { "key": "value" },
          "confidence": 0.9
        }
      PROMPT
    end
  end

  let(:tools) do
    AgentRuntime::ToolRegistry.new({
                                     "search" => lambda do |query:|
                                       {
                                         results: [
                                           { title: "Result 1 for #{query}", url: "https://example.com/1" },
                                           { title: "Result 2 for #{query}", url: "https://example.com/2" }
                                         ],
                                         count: 2
                                       }
                                     end,
                                     "calculate" => lambda do |expression:|
                                       result = eval(expression) # rubocop:disable Security/Eval
                                       { result: result, expression: expression }
                                     end,
                                     "get_time" => lambda do |**_kwargs|
                                       {
                                         current_time: Time.now.utc.iso8601,
                                         timezone: "UTC"
                                       }
                                     end
                                   })
  end

  let(:planner) do
    AgentRuntime::Planner.new(
      client: mock_client,
      schema: schema,
      prompt_builder: prompt_builder
    )
  end

  let(:policy) { AgentRuntime::Policy.new }
  let(:executor) { AgentRuntime::Executor.new(tool_registry: tools) }
  let(:state) { AgentRuntime::State.new }

  describe "Agent#step usage pattern" do
    it "executes single step with search action" do
      llm_response = {
        "action" => "search",
        "params" => { "query" => "Ruby programming tutorials" },
        "confidence" => 0.9
      }

      allow(mock_client).to receive(:generate).and_return(llm_response)

      agent = AgentRuntime::Agent.new(
        planner: planner,
        policy: policy,
        executor: executor,
        state: state
      )

      result = agent.step(input: "Search for Ruby programming tutorials")

      expect(result).to be_a(Hash)
      expect(result[:results]).to be_an(Array)
      expect(result[:count]).to eq(2)
      expect(mock_client).to have_received(:generate)
    end

    it "executes single step with calculate action" do
      llm_response = {
        "action" => "calculate",
        "params" => { "expression" => "15 * 23" },
        "confidence" => 0.9
      }

      allow(mock_client).to receive(:generate).and_return(llm_response)

      agent = AgentRuntime::Agent.new(
        planner: planner,
        policy: policy,
        executor: executor,
        state: state
      )

      result = agent.step(input: "Calculate 15 * 23")

      expect(result).to be_a(Hash)
      expect(result[:result]).to eq(345)
      expect(result[:expression]).to eq("15 * 23")
    end

    it "executes single step with get_time action" do
      llm_response = {
        "action" => "get_time",
        "params" => {},
        "confidence" => 1.0
      }

      allow(mock_client).to receive(:generate).and_return(llm_response)

      agent = AgentRuntime::Agent.new(
        planner: planner,
        policy: policy,
        executor: executor,
        state: state
      )

      result = agent.step(input: "Get the current time")

      expect(result).to be_a(Hash)
      expect(result[:current_time]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      expect(result[:timezone]).to eq("UTC")
    end

    it "handles finish action correctly" do
      llm_response = {
        "action" => "finish",
        "params" => {},
        "confidence" => 1.0
      }

      allow(mock_client).to receive(:generate).and_return(llm_response)

      agent = AgentRuntime::Agent.new(
        planner: planner,
        policy: policy,
        executor: executor,
        state: state
      )

      result = agent.step(input: "Complete the task")

      expect(result).to eq({ done: true })
    end
  end

  describe "Agent#run usage pattern" do
    it "runs multi-step workflow until finish" do
      responses = [
        { "action" => "get_time", "params" => {}, "confidence" => 0.9 },
        { "action" => "finish", "params" => {}, "confidence" => 1.0 }
      ]

      allow(mock_client).to receive(:generate).and_return(*responses)

      agent = AgentRuntime::Agent.new(
        planner: planner,
        policy: policy,
        executor: executor,
        state: AgentRuntime::State.new,
        max_iterations: 3
      )

      result = agent.run(initial_input: "Get the current time, then use the finish action")

      expect(result).to be_a(Hash)
      expect(result[:done]).to be true
      expect(result[:iterations]).to eq(2)
    end

    it "respects max_iterations limit" do
      allow(mock_client).to receive(:generate).and_return(
        { "action" => "search", "params" => { "query" => "test" }, "confidence" => 0.9 }
      )

      agent = AgentRuntime::Agent.new(
        planner: planner,
        policy: policy,
        executor: executor,
        state: state,
        max_iterations: 2
      )

      expect { agent.run(initial_input: "Search") }
        .to raise_error(AgentRuntime::MaxIterationsExceeded)
    end
  end

  describe "AgentFSM usage pattern" do
    # Custom FSM class matching the example pattern
    class ExampleAgentFSM < AgentRuntime::AgentFSM
      def build_tools_for_chat
        tools_hash = @tool_registry.instance_variable_get(:@tools) || {}
        return [] if tools_hash.empty?

        tools_hash.keys.map { |tool_name| build_tool_schema(tool_name) }
      end

      private

      def build_tool_schema(tool_name)
        {
          type: "function",
          function: {
            name: tool_name.to_s,
            description: tool_description(tool_name),
            parameters: tool_parameters(tool_name)
          }
        }
      end

      def tool_description(tool_name)
        TOOL_DESCRIPTIONS.fetch(tool_name.to_s, "Tool: #{tool_name}")
      end

      def tool_parameters(tool_name)
        {
          type: "object",
          properties: tool_properties(tool_name),
          required: tool_required_params(tool_name)
        }
      end

      def tool_properties(tool_name)
        TOOL_PROPERTIES.fetch(tool_name.to_s, {})
      end

      def tool_required_params(tool_name)
        TOOL_REQUIRED.fetch(tool_name.to_s, [])
      end

      TOOL_DESCRIPTIONS = {
        "search" => "Search for information. Requires 'query' parameter.",
        "calculate" => "Perform calculations. Requires 'expression' parameter (e.g., '2+2').",
        "get_time" => "Get current time. No parameters required."
      }.freeze

      TOOL_PROPERTIES = {
        "search" => { query: { type: "string", description: "Search query" } },
        "calculate" => { expression: { type: "string", description: "Mathematical expression" } },
        "get_time" => {}
      }.freeze

      TOOL_REQUIRED = {
        "search" => ["query"],
        "calculate" => ["expression"],
        "get_time" => []
      }.freeze
    end

    it "completes full FSM workflow" do
      plan_response = {
        "action" => "plan",
        "params" => {
          "goal" => "Search for information",
          "required_capabilities" => ["search"],
          "initial_steps" => []
        },
        "confidence" => 0.9
      }

      execute_response = {
        "message" => {
          "content" => "I have completed the search.",
          "tool_calls" => nil
        }
      }

      allow(mock_client).to receive_messages(generate: plan_response, chat_raw: execute_response)
      allow(mock_client).to receive(:instance_variable_get).with(:@schema).and_return(schema)
      allow(mock_client).to receive(:instance_variable_get).with(:@prompt_builder)
                                                           .and_return(prompt_builder)

      agent_fsm = ExampleAgentFSM.new(
        planner: planner,
        policy: policy,
        executor: executor,
        state: AgentRuntime::State.new,
        tool_registry: tools,
        max_iterations: 10
      )

      result = agent_fsm.run(initial_input: "Search for information about Ruby agents")

      if result.nil?
        expect(agent_fsm.fsm.terminal?).to be true
      else
        expect(result).to be_a(Hash)
        expect(result[:done]).to be true
        expect(result).to have_key(:iterations)
        expect(result).to have_key(:state)
        expect(result).to have_key(:fsm_history)
      end
    end

    it "handles workflow with tool calls" do
      plan_response = {
        "action" => "plan",
        "params" => {
          "goal" => "Calculate and search",
          "required_capabilities" => %w[calculate search],
          "initial_steps" => []
        }
      }

      tool_call_response = {
        "message" => {
          "content" => "",
          "tool_calls" => [
            {
              "id" => "call_1",
              "function" => {
                "name" => "calculate",
                "arguments" => '{"expression":"2 + 2"}'
              }
            }
          ]
        }
      }

      final_response = {
        "message" => {
          "content" => "Calculation complete: 4",
          "tool_calls" => nil
        }
      }

      allow(mock_client).to receive(:generate).and_return(plan_response)
      allow(mock_client).to receive(:chat_raw)
        .and_return(tool_call_response, final_response)
      allow(mock_client).to receive(:instance_variable_get).with(:@schema).and_return(schema)
      allow(mock_client).to receive(:instance_variable_get).with(:@prompt_builder)
                                                           .and_return(prompt_builder)

      agent_fsm = ExampleAgentFSM.new(
        planner: planner,
        policy: policy,
        executor: executor,
        state: AgentRuntime::State.new,
        tool_registry: tools,
        max_iterations: 10
      )

      result = agent_fsm.run(initial_input: "Calculate 2+2 and tell me the result")

      if result.nil?
        expect(agent_fsm.fsm.terminal?).to be true
      else
        expect(result[:done]).to be true
      end

      expect(agent_fsm.messages.any? { |m| m[:role] == "tool" }).to be true
    end
  end

  describe "state persistence pattern" do
    it "maintains state across multiple steps" do
      responses = [
        { "action" => "search", "params" => { "query" => "first" }, "confidence" => 0.9 },
        { "action" => "search", "params" => { "query" => "second" }, "confidence" => 0.9 }
      ]

      allow(mock_client).to receive(:generate).and_return(*responses)

      agent = AgentRuntime::Agent.new(
        planner: planner,
        policy: policy,
        executor: executor,
        state: state
      )

      agent.step(input: "First search")
      first_state = state.snapshot.dup
      first_keys_count = first_state.keys.length

      agent.step(input: "Second search")
      second_state = state.snapshot

      expect(second_state).to be_a(Hash)
      expect(second_state.keys.length).to be >= first_keys_count
    end
  end

  describe "error handling pattern" do
    it "handles tool execution errors gracefully" do
      llm_response = {
        "action" => "search",
        "params" => { "query" => "test" },
        "confidence" => 0.9
      }

      error_tools = AgentRuntime::ToolRegistry.new({
                                                     "search" => ->(**_args) { raise StandardError, "Tool error" }
                                                   })

      allow(mock_client).to receive(:generate).and_return(llm_response)

      agent = AgentRuntime::Agent.new(
        planner: planner,
        policy: policy,
        executor: AgentRuntime::Executor.new(tool_registry: error_tools),
        state: state
      )

      expect { agent.step(input: "Search") }
        .to raise_error(AgentRuntime::ExecutionError, /Tool error/)
    end

    it "handles missing tools correctly" do
      llm_response = {
        "action" => "unknown_tool",
        "params" => {},
        "confidence" => 0.9
      }

      allow(mock_client).to receive(:generate).and_return(llm_response)

      agent = AgentRuntime::Agent.new(
        planner: planner,
        policy: policy,
        executor: executor,
        state: state
      )

      expect { agent.step(input: "Use unknown tool") }
        .to raise_error(AgentRuntime::ExecutionError, /Tool not found/)
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers, RSpec/DescribeClass
