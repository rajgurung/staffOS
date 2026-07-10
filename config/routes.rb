Rails.application.routes.draw do
  devise_for :users, controllers: {
    sessions: "users/sessions"
  }
  get "up" => "rails/health#show", as: :rails_health_check

  root "landing#index"

  get "dashboard", to: "dashboard#index", as: :dashboard
  post "switch_project", to: "application#switch_project", as: :switch_project
  get "risk_cockpit", to: "risk_cockpit#index", as: :risk_cockpit
  get "connect", to: "connect#index", as: :connect
  get "connect/script", to: "connect#script", as: :connect_script
  get "settings", to: "settings#index", as: :settings
  patch "settings/profile", to: "settings#update_profile", as: :update_profile_settings

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

      # Claude Code HTTP hook endpoints
      post "hooks/session_start", to: "hooks#session_start"
      post "hooks/prompt", to: "hooks#prompt"
      post "hooks/pre_tool", to: "hooks#pre_tool"
      post "hooks/post_tool", to: "hooks#post_tool"
      post "hooks/stop", to: "hooks#stop"
    end
  end
end
