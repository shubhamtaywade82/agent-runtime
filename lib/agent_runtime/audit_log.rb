# frozen_string_literal: true

require "json"

module AgentRuntime
  # Optional audit logging for agent decisions and results
  class AuditLog
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
