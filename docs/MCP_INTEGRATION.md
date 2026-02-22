# Model Context Protocol (MCP) Integration

AgentRuntime provides native support for the [Model Context Protocol (MCP)](https://modelcontextprotocol.io), allowing you to expand your agent's capabilities with tools from a vast ecosystem of remote and local servers.

## Overview

The integration bridges the `mcp-ruby` client directly into the `AgentRuntime::ToolRegistry`. This allows any LLM configured via `AgentRuntime::Planner` to discover and use MCP-hosted tools as if they were native Ruby callables.

## Key Features

- **Dynamic Tool Registration**: Automatically sync schemas and tool metadata from MCP servers.
- **Support for All Transports**: Compatiable with HTTP, Stdio, and custom transports.
- **Robust CLI Support**: Includes a specialized `CLIStdioTransport` using PTY to solve buffering issues with persistent Node.js servers (like `npx mcp-remote`).
- **Multi-Server Support**: Register multiple MCP servers into a single agent runtime.

## Basic Usage

To integrate a simple MCP server via HTTP:

```ruby
require "agent_runtime"
require "mcp"

# 1. Setup the MCP Client
transport = MCP::Client::HTTP.new(url: "https://your-mcp-server.com/tools")
mcp_client = MCP::Client.new(transport: transport)

# 2. Register into the ToolRegistry
tools = AgentRuntime::ToolRegistry.new
tools.register_mcp_client(mcp_client)

# 3. Running the Agent
agent = AgentRuntime::AgentFSM.new(
  planner: AgentRuntime::Planner.new(client: Ollama::Client.new, model: "llama3.2"),
  tool_registry: tools
)

agent.run(initial_input: "Use the remote tool to fetch data.")
```

## Advanced: Connecting to Remote Repositories (`npx mcp-remote`)

Standard I/O between Ruby and Node.js often suffers from buffering delays. We recommend using a Pseudo-Terminal (PTY) transport for persistent CLI tools.

### `CLIStdioTransport` Example

You can find the implementation of `CLIStdioTransport` in [examples/git_mcp_example.rb](file:///home/nemesis/project/agent-runtime/examples/git_mcp_example.rb). It ensures that the remote process flushes its output immediately.

```ruby
# Spawning a remote Git bridge
transport = CLIStdioTransport.new("npx", "-y", "mcp-remote", "https://github.com/user/repo")
mcp_client = MCP::Client.new(transport: transport)

# Note: many CLI servers require a manual handshake
transport.send_request(request: {
  jsonrpc: "2.0", id: "1", method: "initialize", params: { ... }
})
```

## Multi-Repository Integration

You can register multiple repositories into a single unified registry:

```ruby
repos = ["repo-a-url", "repo-b-url"]
tools = AgentRuntime::ToolRegistry.new

repos.each do |url|
  transport = CLIStdioTransport.new("npx", "mcp-remote", url)
  client = MCP::Client.new(transport: transport)
  tools.register_mcp_client(client)
end

# The agent can now cross-reference tools from ALL repositories!
```

## Internal Safeguards

The `ToolRegistry` automatically symbolizes parameter keys from MCP payloads to ensure compatibility with Ruby's keyword argument extension (`**arguments`). This prevents `ArgumentError` when passing raw JSON strings.
