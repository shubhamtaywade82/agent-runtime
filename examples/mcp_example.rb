#!/usr/bin/env ruby
# frozen_string_literal: true

# Example demonstrating how to use the Model Context Protocol (MCP) with AgentRuntime.
# Copy-paste this into bin/console or run it via `bundle exec ruby examples/mcp_example.rb`

require "agent_runtime"
require "ollama_client"
require "mcp"

puts "Setting up MCP Integration Example..."
puts "=" * 60

# 1. Start by initializing your AgentRuntime tool registry
tools = AgentRuntime::ToolRegistry.new

# 2. In a real world application, you would connect to an MCP Server using an HTTP transport:
#
# require "faraday"
# http_transport = MCP::Client::HTTP.new(url: "https://api.example.com/mcp")
# mcp_client = MCP::Client.new(transport: http_transport)
#
# For this example, we'll create a mock MCP Client that simulates a remote server
# offering a "get_weather" tool.
class MockMCPClient
  # Mock tool implementation simulating an MCP remote tool
  class MockTool
    attr_reader :name, :description, :input_schema

    def initialize(name:, description:, input_schema:)
      @name = name
      @description = description
      @input_schema = input_schema
    end
  end

  def tools
    [
      MockTool.new(
        name: "get_weather",
        description: "Get the current weather for a location",
        input_schema: {
          "type" => "object",
          "properties" => {
            "location" => { "type" => "string", "description" => "The city name" }
          },
          "required" => ["location"]
        }
      )
    ]
  end

  def call_tool(tool:, arguments:)
    puts "\n[MCP SERVER] 🌐 Received remote request for '#{tool.name}' with args: #{arguments.inspect}"
    # Simulate a network latency
    sleep 0.5
    { "weather" => "Sunny, 72°F", "location" => arguments[:location] || arguments["location"] }
  end
end

mcp_client = MockMCPClient.new

# 3. Register the MCP client's tools natively into the AgentRuntime ToolRegistry
puts "Registering tools from remote MCP Server..."
registered_tools = tools.register_mcp_client(mcp_client)
puts "Successfully registered remote tools: #{registered_tools.join(", ")}"
puts "\nTools Registry state:"
puts "Schema for 'get_weather': #{tools.schema_for("get_weather")}"

# 4. Set up an Agent to use these remote tools natively!
client = Ollama::Client.new
# Using a simple deterministic planning schema since we're going to execute it
planner = AgentRuntime::Planner.new(
  client: client,
  schema: {
    "type" => "object",
    "required" => %w[action params confidence],
    "properties" => {
      "action" => { "type" => "string", "enum" => %w[get_weather finish] },
      "params" => { "type" => "object", "additionalProperties" => true },
      "confidence" => { "type" => "number", "minimum" => 0, "maximum" => 1 }
    }
  },
  prompt_builder: lambda { |input:, _state:|
    "User request: #{input}\nAvailable tools: get_weather."
  }
)

agent = AgentRuntime::Agent.new(
  planner: planner,
  executor: AgentRuntime::Executor.new(tool_registry: tools),
  policy: AgentRuntime::Policy.new,
  state: AgentRuntime::State.new
)

puts "\nExecuting Agent Step utilizing the remote MCP tool..."
puts "-" * 60

begin
  result = agent.step(input: "What is the weather in San Francisco?")
  puts "\n✅ Agent Execution Success!"
  puts "Result from agent: #{result.inspect}"
rescue StandardError => e
  puts "\n❌ Execution Error: #{e.message}"
  puts "(Ensure your Ollama server is running locally if you get connection errors)"
end
