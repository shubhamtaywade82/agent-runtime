# frozen_string_literal: true

require "agent_runtime"
require "ollama_client"
require "mcp"

require "json"
require "pty"

# An unbuffered I/O transport for MCP CLI tools using a Pseudo-Terminal.
# Node.js holds onto stdout buffers unless it thinks it is attached to a real TTY.
class CLIStdioTransport
  def initialize(*cmd)
    @out, @in, @pid = PTY.spawn(*cmd)

    # We must swallow the initial boot logs to sync up the json streams!
    # rubocop:disable ThreadSafety/NewThread
    Thread.new do
      loop do
        line = @out.gets
        break if line.nil? || line.include?("Proxy established successfully")
      rescue Errno::EIO
        break
      end
    end.join(5) # Give it 5s to boot
    # rubocop:enable ThreadSafety/NewThread
  end

  def send_request(request:)
    escaped_json = request.to_json
    puts "[send_request] OUT: #{escaped_json}" if ENV["DEBUG_MCP"]
    @in.puts(escaped_json)

    # Notifications do not receive responses
    return nil if request[:method]&.start_with?("notifications/")

    response = read_response
    puts "[send_request] IN: #{response.to_json}" if ENV["DEBUG_MCP"]
    response
  rescue StandardError => e
    warn "Failed to communicate with remote MCP server: #{e.message}"
    raise e
  end

  def close
    @in.close
    @out.close
    Process.kill("KILL", @pid) if @pid
  end

  private

  def read_response
    loop do
      line = @out.gets
      raise "No response from MCP server" if line.nil?
      next if line.strip.empty?

      # PTY sometimes echos the input command back to stdout, filter it out
      next if line.include?("jsonrpc") && !line.start_with?("{")
      next unless line.start_with?("{")

      result = parse_json_rpc(line)
      return result if result
    end
  rescue Errno::EIO
    warn "MCP Server exited prematurely."
    raise "No response from MCP server"
  end

  def parse_json_rpc(line)
    parsed = JSON.parse(line)
    # Make sure this isn't just PTY echoing our STDIN back to us (must have result/error)
    return parsed if parsed.key?("result") || parsed.key?("error")

    nil
  rescue JSON::ParserError
    nil
  end
end

REPOSITORIES = [
  "https://gitmcp.io/shubhamtaywade82/dhanhq-client",
  "https://gitmcp.io/shubhamtaywade82/algo_trading_api",
  "https://gitmcp.io/shubhamtaywade82/algo_scalper_api"
].freeze

tools = AgentRuntime::ToolRegistry.new
transports = []

puts "Starting npx mcp-remote bridges to gitmcp.io..."

REPOSITORIES.each do |repo_url|
  repo_name = repo_url.split("/").last
  puts "\n--> Connecting to repository: #{repo_name}..."

  begin
    transport = CLIStdioTransport.new("npx", "-y", "mcp-remote", repo_url)
    transports << transport

    mcp_client = MCP::Client.new(transport: transport)

    init_response = transport.send_request(request: {
                                             jsonrpc: "2.0",
                                             id: "init-#{repo_name}",
                                             method: "initialize",
                                             params: {
                                               protocolVersion: "2024-11-05",
                                               capabilities: {},
                                               clientInfo: { name: "AgentRuntime", version: "1.0.0" }
                                             }
                                           })

    transport.send_request(request: {
                             jsonrpc: "2.0",
                             method: "notifications/initialized"
                           })

    registered = tools.register_mcp_client(mcp_client)
    puts "✅ Handshook #{init_response.dig("result", "serverInfo", "name")} and registered #{registered.size} tools."
  rescue StandardError => e
    warn "❌ Failed to connect to #{repo_name}: #{e.message}"
  end
end

remote_tool_names = tools.instance_variable_get(:@tools).keys
puts "\nTOTAL registered remote tools: #{remote_tool_names.size}"

# Generate a restrictive planner schema that strictly binds the tools
planner_schema = {
  "type" => "object",
  "required" => %w[action params confidence],
  "properties" => {
    "action" => {
      "type" => "string",
      "enum" => remote_tool_names + ["finish"],
      "description" => "The exact tool call to make, or 'finish' to stop executing."
    },
    "params" => {
      "type" => "object",
      "additionalProperties" => true,
      "description" => "The parameters to pass into the tool."
    },
    "confidence" => {
      "type" => "number",
      "description" => "A probability between 0 and 1 estimating success."
    }
  }
}

# Add a simple policy to ensure tools are valid
class MCPPolicy < AgentRuntime::Policy
  def validate!(decision, _state = nil)
    raise PolicyViolation, "Missing action" unless decision.action
  end

  def converged?(state)
    state.snapshot[:final_message] || false
  end
end

MODEL_NAME = "llama3.1:8b-instruct-q4_K_M"
puts "\nBooting up local Model: #{MODEL_NAME}"

# Instantiate the final FSM looping Agent
agent = AgentRuntime::AgentFSM.new(
  planner: AgentRuntime::Planner.new(
    client: Ollama::Client.new,
    model: MODEL_NAME,
    schema: planner_schema,
    prompt_builder: lambda { |input:, state:|
      <<~PROMPT
        GOAL: #{input}

        You are an advanced agent with access to multiple remote GitHub repository tools.
        IMPORTANT:
        1. Always use the specialized 'fetch_*_documentation' tools FIRST to understand the specific repository referenced.
        2. Do NOT construct or guess GitHub URLs for 'fetch_generic_url_content'.
        3. Output ONLY valid JSON action payloads. No conversational filler.

        AVAILABLE TOOLS: #{remote_tool_names.join(", ")}

        CURRENT STATE: #{state.to_json}
      PROMPT
    }
  ),
  tool_registry: tools,
  executor: AgentRuntime::Executor.new(tool_registry: tools),
  policy: MCPPolicy.new,
  state: AgentRuntime::State.new
)

# Go!
query = ARGV.empty? ? "Read the README files inside the repositories" : ARGV.join(" ")

puts "\nRunning query: '#{query}'"
puts "..."

begin
  result = agent.run(initial_input: query)

  puts "\nFinal Result:"
  puts result[:final_message] || result.inspect
ensure
  # Cleanup transports
  transports.each(&:close)
end
