# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

# Coverage task - runs specs with coverage reporting
RSpec::Core::RakeTask.new(:coverage) do |t|
  t.rspec_opts = "--format documentation"
end

require "rubocop/rake_task"

RuboCop::RakeTask.new

task default: %i[spec rubocop]
