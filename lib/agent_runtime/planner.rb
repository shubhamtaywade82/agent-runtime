# frozen_string_literal: true

require "json"

module AgentRuntime
  class Planner
    def initialize(client:, schema:)
      @client = client
      @schema = schema
    end

    def plan(input:, state:)
      prompt = build_prompt(input, state)
      response = @client.generate(prompt: prompt, schema: @schema)
      normalize_response(response)
    end

    private

    def build_prompt(input, state)
      "Input: #{input}\nState: #{JSON.generate(state)}"
    end

    def normalize_response(response)
      Decision.new(
        action: response["action"],
        params: response["params"] || {},
        confidence: response["confidence"] || 1.0
      )
    end
  end
end
