# frozen_string_literal: true

Rails.application.routes.draw do
  namespace :assistants do
    post "billing", to: "assistants#billing"
  end

  # Optional: WebSocket endpoint for real-time updates
  # mount ActionCable.server => "/cable"
end
