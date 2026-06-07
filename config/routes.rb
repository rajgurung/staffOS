Rails.application.routes.draw do
  devise_for :users, controllers: {
    sessions: "users/sessions",
    registrations: "users/registrations"
  }
  get "up" => "rails/health#show", as: :rails_health_check

  root "dashboard#index"

  get "dashboard", to: "dashboard#index", as: :dashboard
  get "risk_cockpit", to: "risk_cockpit#index", as: :risk_cockpit

  resources :workstreams, only: [:index, :show, :edit, :update] do
    member do
      post :promote
    end
  end
  resources :agent_sessions, path: "runs", as: :runs, only: [:index, :show]
  resources :run_passports, only: [:index, :show] do
    member do
      post :run_council
      post :generate_document
      post :set_review_mode
      get :export
    end
  end

  get "search", to: "search#index", as: :search
  resources :documents
  resources :decision_logs
  resources :memory_items, path: "memory", as: :memory_items
  resources :projects do
    resources :api_tokens, only: [:create, :destroy]
    member do
      get :hook_config
    end
  end

  namespace :api do
    namespace :v1 do
      resources :events, only: [:create]
      post "sessions/:session_id/complete", to: "sessions#complete"
    end
  end
end
