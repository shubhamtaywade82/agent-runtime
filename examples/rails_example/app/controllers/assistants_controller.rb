# frozen_string_literal: true

# Rails controller exposing agent through web interface
# This demonstrates the correct pattern: UI → Controller → Agent → Result
class AssistantsController < ApplicationController
  before_action :authenticate_user!

  # POST /assistants/billing
  # Body: { question: "Why was invoice #123 charged twice?" }
  #
  # For single-step queries, use agent.step()
  # For multi-step workflows (e.g., fetch invoice then analyze), use agent.run()
  def billing
    question = params.require(:question)
    use_multi_step = params[:multi_step] == "true"

    agent = BillingAgent.instance

    # Single-step: one decision, one execution
    # Multi-step: loop until convergence or max iterations
    result = if use_multi_step
               agent.run(initial_input: question)
             else
               agent.step(input: question)
             end

    # Extract progress signals if available (for debugging/monitoring)
    progress_signals = if agent.state.respond_to?(:progress)
                         agent.state.progress.signals
                       else
                         []
                       end

    render json: {
      answer: result[:analysis] || result[:explanation],
      confidence: extract_confidence(result),
      metadata: result.except(:analysis, :explanation),
      progress_signals: progress_signals,
      converged: use_multi_step && agent.state.respond_to?(:progress) &&
                 agent.state.progress.include?(:tool_called)
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
