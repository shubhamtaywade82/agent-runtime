# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
  add_filter "/.bundle/"
  add_filter "/vendor/"

  # Track all lib files
  track_files "lib/**/*.rb"

  # Minimum coverage threshold (warn only, doesn't fail build)
  # Set COVERAGE_THRESHOLD environment variable to enforce a threshold
  minimum_coverage ENV["COVERAGE_THRESHOLD"].to_f if ENV["COVERAGE_THRESHOLD"]

  # Coverage formatters
  formatter SimpleCov::Formatter::MultiFormatter.new([
                                                       SimpleCov::Formatter::SimpleFormatter,
                                                       SimpleCov::Formatter::HTMLFormatter
                                                     ])
end

require "agent_runtime"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
