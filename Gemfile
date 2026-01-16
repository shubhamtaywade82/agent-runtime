# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in agent-runtime.gemspec
gemspec

gem "irb"
gem "rake", "~> 13.0"

gem "rspec", "~> 3.0"
gem "simplecov", "~> 0.22", require: false, group: :test

gem "rubocop", "~> 1.21"
gem "rubocop-performance"
gem "rubocop-rake"
gem "rubocop-rspec"
gem "rubocop-thread_safety"

# DhanHQ integration for Indian market data (development only)
gem "DhanHQ", git: "https://github.com/shubhamtaywade82/dhanhq-client.git", branch: "main", group: :development
gem "dotenv", group: :development
