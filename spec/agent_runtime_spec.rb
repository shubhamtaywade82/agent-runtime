# frozen_string_literal: true

RSpec.describe AgentRuntime do
  it "has a version number" do
    expect(AgentRuntime::VERSION).not_to be_nil
  end
end
