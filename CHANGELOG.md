## [0.3.0] - 2026-02-22

### Added
- Native support for Model Context Protocol (MCP) in `ToolRegistry#register_mcp_client`
- Enhanced support for JSON-RPC `initialize` handshake for remote MCP servers
- Documentation for Multimodal/Vision model integration including Base64 requirements
- Support for "Thinking" (Reasoning) models via `think: true` parameter in `Planner`
- Multi-repository MCP bridge support using PTY-based `CLIStdioTransport`

### Fixed
- `ToolRegistry#call` now symbolizes all parameter keys, preventing `ArgumentError` during keyword argument expansion
- `Executor#execute` now includes detailed logging for rescued exceptions
- Fixed `Planner` parameter passing to ensure `options` are correctly prioritized for Ollama execution

## [0.2.0] - 2026-01-XX

### Fixed
- FSM finalization now properly executes `handle_finalize` or `handle_halt` before returning
- Agent#run now always returns the last tool result when terminating
- Tool call argument parsing now handles JSON parse failures gracefully
- Audit logging now handles nil decisions without crashing

### Changed
- Removed domain-specific code (DhanHQ helpers) from `lib/` directory
- Planning contract for FSM is now documented and consistent
- Tool calls are now enabled in FSM with basic tool definition conversion
- State#apply! now performs deep merge of nested hashes
- Removed hardcoded local paths from examples (now uses environment variables)

### Documentation
- Updated README to remove references to deleted console helpers
- Fixed documentation to match actual behavior
- Removed CONSOLE_TESTING.md (domain-specific content)

## [0.1.0] - 2026-01-15

- Initial release
