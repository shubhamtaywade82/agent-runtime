# frozen_string_literal: true

# Rails controller exposing agent through web interface
# This demonstrates the correct pattern: UI → Controller → Agent → Result
class AssistantsController < ApplicationController
  before_action :authenticate_user!

  # POST /assistants/billing
  # Body: { question: "Why was invoice #123 charged twice?" }
  def billing
    question = params.require(:question)

    result = BillingAgent.instance.step(input: question)

    render json: {
      answer: result[:analysis] || result[:explanation],
      confidence: extract_confidence(result),
      metadata: result.except(:analysis, :explanation)
    }
  rescue AgentRuntime::PolicyViolation => e
    render json: { error: "Policy violation: #{e.message}" }, status: :unprocessable_entity
  rescue AgentRuntime::ExecutionError => e
    render json: { error: "Execution failed: #{e.message}" }, status: :internal_server_error
  end

  private

  def extract_confidence(result)
    result[:confidence] || 0.5
  end
end
