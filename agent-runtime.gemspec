# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "agent_runtime"
  spec.version = "0.2.0"
  spec.authors = ["Shubham Taywade"]
  spec.email = ["shubhamtaywade82@gmail.com"]

  spec.summary = "Deterministic, policy-driven runtime for safe LLM agents"
  spec.description = "AgentRuntime provides a reusable control plane for building " \
                     "tool-using LLM agents with explicit state, policy enforcement, and auditability."
  spec.homepage = "https://github.com/shubhamtaywade/agent-runtime"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir["lib/**/*", "README.md", "LICENSE.txt", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "ollama-client", ">= 0.1.0"
  spec.metadata["rubygems_mfa_required"] = "true"
end
