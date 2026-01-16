# frozen_string_literal: true

require "spec_helper"

RSpec.describe AgentRuntime::Error do
  it "is a StandardError" do
    expect(described_class.superclass).to eq(StandardError)
  end

  it "can be raised and rescued" do
    expect { raise described_class, "test" }.to raise_error(described_class, "test")
  end
end

RSpec.describe AgentRuntime::PolicyViolation do
  it "inherits from Error" do
    expect(described_class.superclass).to eq(AgentRuntime::Error)
  end

  it "can be raised with a message" do
    expect { raise described_class, "Invalid decision" }
      .to raise_error(described_class, "Invalid decision")
  end
end

RSpec.describe AgentRuntime::UnknownAction do
  it "inherits from Error" do
    expect(described_class.superclass).to eq(AgentRuntime::Error)
  end

  it "can be raised with a message" do
    expect { raise described_class, "Unknown action: invalid" }
      .to raise_error(described_class, "Unknown action: invalid")
  end
end

RSpec.describe AgentRuntime::ToolNotFound do
  it "inherits from Error" do
    expect(described_class.superclass).to eq(AgentRuntime::Error)
  end

  it "can be raised with a message" do
    expect { raise described_class, "Tool not found: missing" }
      .to raise_error(described_class, "Tool not found: missing")
  end
end

RSpec.describe AgentRuntime::ExecutionError do
  it "inherits from Error" do
    expect(described_class.superclass).to eq(AgentRuntime::Error)
  end

  it "can be raised with a message" do
    expect { raise described_class, "Execution failed" }
      .to raise_error(described_class, "Execution failed")
  end
end

RSpec.describe AgentRuntime::MaxIterationsExceeded do
  it "inherits from ExecutionError" do
    expect(described_class.superclass).to eq(AgentRuntime::ExecutionError)
  end

  it "can be raised with a message" do
    expect { raise described_class, "Max iterations exceeded: 50" }
      .to raise_error(described_class, "Max iterations exceeded: 50")
  end

  it "is also an ExecutionError" do
    expect { raise described_class, "test" }
      .to raise_error(AgentRuntime::ExecutionError, "test")
  end
end
