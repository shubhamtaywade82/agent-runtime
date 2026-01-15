# frozen_string_literal: true

module AgentRuntime
  class Planner
    def initialize(client:, schema:, prompt_builder:)
      @client = client
      @schema = schema
      @prompt_builder = prompt_builder
    end

    def plan(input:, state:)
      raw = @client.generate(
        prompt: @prompt_builder.call(input: input, state: state),
        schema: @schema
      )

      Decision.new(**raw.transform_keys(&:to_sym))
    end
  end
end
