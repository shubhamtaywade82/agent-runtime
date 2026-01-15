# frozen_string_literal: true

require_relative "lib/agent_runtime/version"

Gem::Specification.new do |spec|
  spec.name = "agent-runtime"
  spec.version = AgentRuntime::VERSION
  spec.authors = ["Shubham Taywade"]
  spec.email = ["shubhamtaywade82@gmail.com"]

  spec.summary = "A deterministic, policy-driven runtime for building safe, tool-using LLM agents"
  spec.description = "AgentRuntime is a domain-agnostic agent runtime that provides explicit state management, policy enforcement, and tool execution for LLM-based agents. It separates reasoning (LLM) from authority (Ruby) and gates all side effects."
  spec.homepage = "https://github.com/shubhamtaywade/agent-runtime"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/ .rubocop.yml examples/])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "ollama-client", "~> 1.0"
end
