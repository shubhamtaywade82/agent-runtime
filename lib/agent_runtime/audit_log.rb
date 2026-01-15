# frozen_string_literal: true

require "json"

module AgentRuntime
  class AuditLog
    def record(input:, decision:, result:)
      puts({
        time: Time.now.utc.iso8601,
        input: input,
        decision: decision.to_h,
        result: result
      }.to_json)
    end
  end
end
