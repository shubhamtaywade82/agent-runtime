# frozen_string_literal: true

# AgentRuntime configuration for Rails
# This is where you configure shared agent settings

Rails.application.config.agent_runtime = ActiveSupport::OrderedOptions.new

# Default Ollama URL
Rails.application.config.agent_runtime.ollama_url = ENV.fetch(
  "OLLAMA_URL",
  "http://localhost:11434"
)

# Default timeout for agent operations
Rails.application.config.agent_runtime.timeout = 30.seconds

# Enable audit logging in production
Rails.application.config.agent_runtime.audit_enabled = Rails.env.production?
