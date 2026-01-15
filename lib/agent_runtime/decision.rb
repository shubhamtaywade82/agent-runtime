# frozen_string_literal: true

module AgentRuntime
  Decision = Struct.new(
    :action,
    :params,
    :confidence,
    keyword_init: true
  )
end
