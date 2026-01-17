# frozen_string_literal: true

require "json"

module AgentRuntime
  # Optional audit logging for agent decisions and results.
  #
  # This class provides a simple audit logging mechanism that records
  # agent inputs, decisions, and results as JSON to stdout.
  #
  # Subclass this to implement custom logging (e.g., to a file or database).
  #
  # @example Basic usage
  #   audit_log = AuditLog.new
  #   audit_log.record(input: "Search", decision: decision, result: { result: "..." })
  #
  # @example Custom audit log implementation
  #   class DatabaseAuditLog < AuditLog
  #     def record(input:, decision:, result:)
  #       super  # Still log to stdout
  #       AuditRecord.create(input: input, decision: decision, result: result)
  #     end
  #   end
  class AuditLog
    # Record an audit log entry.
    #
    # Outputs a JSON object to stdout containing:
    # - time: ISO8601 timestamp
    # - input: The input that triggered the decision
    # - decision: The decision made (converted to hash if possible)
    # - result: The execution result
    #
    # @param input [String, Object] The input that triggered the decision
    # @param decision [Decision, Hash, nil] The decision made (converted to hash if responds to #to_h)
    # @param result [Hash, Object] The execution result
    # @return [void]
    #
    # @example
    #   audit_log.record(
    #     input: "What is the weather?",
    #     decision: Decision.new(action: "search", params: { query: "weather" }),
    #     result: { result: "Sunny, 72°F" }
    #   )
    #   # Outputs: {"time":"2024-01-01T12:00:00Z","input":"What is the weather?",...}
    def record(input:, decision:, result:)
      decision_hash = if decision.nil?
                        nil
                      elsif decision.respond_to?(:to_h)
                        decision.to_h
                      else
                        decision
                      end

      puts({
        time: Time.now.utc.iso8601,
        input: input,
        decision: decision_hash,
        result: result
      }.to_json)
    end
  end
end
