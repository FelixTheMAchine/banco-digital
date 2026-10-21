Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  namespace :api do
    namespace :v1 do
      get "health", to: "health#show"
      namespace :auth do
        post "register", to: "registrations#create"
        post "login", to: "logins#create"
        post "refresh", to: "refreshes#create"
        delete "logout", to: "logouts#destroy"
        post "email_verifications", to: "email_verifications#create"
        patch "email_verifications", to: "email_verifications#update"
        post "password_resets", to: "password_resets#create"
        patch "password_resets", to: "password_resets#update"
      end
      resource :me, only: %i[show update destroy], controller: "me"
      resources :sessions, only: %i[index destroy]
      resource :account, only: %i[show create], controller: "accounts" do
        post "deposits", action: :deposit
        post "withdrawals", action: :withdraw
        post :block
        post :close
      end
      resources :transfers, only: :create
      resources :transactions, only: %i[index show] do
        get :receipt, on: :member
        post :reverse, on: :member
      end
      resources :scheduled_transfers, only: %i[index create destroy]
      get "dashboard", to: "dashboard#show"
      resources :notifications, only: :index do
        patch :read, on: :member
      end
      resources :loan_simulations, only: :create
      resources :loans, only: %i[index show create] do
        resources :appeals, only: :create, controller: "loan_appeals"
      end
      resource :investment_profile, only: %i[show create], controller: "investment_profiles"
      resources :investment_products, only: :index
      resources :investment_simulations, only: %i[index show create]
      resources :financial_goals, only: %i[index create update destroy]

      get "security", to: "security/status#show"
      namespace :security do
        post "mfa/enrollment", to: "mfa#enrollment"
        post "mfa/enable", to: "mfa#enable"
        post "mfa/verify", to: "mfa#verify"
        delete "mfa", to: "mfa#destroy"
      end
      namespace :admin do
        get "overview", to: "overview#show"
        resources :users, only: :index
        resources :accounts, only: :index do
          post :block, on: :member
          post :unblock, on: :member
        end
        resources :transactions, only: :index
        resources :security_events, only: :index do
          post :review, on: :member
        end
        resources :loans, only: :index do
          post :review, on: :member
        end
        resources :audit_logs, only: :index
        resource :financial_rules, only: %i[show update], controller: "financial_rules"
        resource :credit_rules, only: %i[show update], controller: "credit_rules"
        get "exports", to: "exports#show", defaults: { format: :xlsx }
      end
    end
  end
end
