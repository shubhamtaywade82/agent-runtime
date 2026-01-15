# frozen_string_literal: true

require "json"

module AgentRuntime
  class AuditLog
    def initialize(output: $stdout)
      @output = output
    end

    def record(input, decision, result)
      entry = {
        input: input,
        decision: {
          action: decision.action,
          params: decision.params,
          confidence: decision.confidence
        },
        result: result,
        time: Time.now.iso8601
      }
      @output.puts(entry.to_json)
    end
  end
end
