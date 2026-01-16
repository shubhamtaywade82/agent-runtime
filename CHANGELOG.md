## [Unreleased]

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
