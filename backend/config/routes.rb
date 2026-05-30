# frozen_string_literal: true

Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  mount ActionCable.server => "/cable"

  namespace :api do
    namespace :v1 do
      namespace :auth do
        post "platform/login", to: "platform_sessions#create"
        post "company/login", to: "company_sessions#create"
        post "reviewer/login", to: "reviewer_sessions#create"
        post "company/signup", to: "company_registrations#create"
        post "reviewer/signup", to: "reviewer_registrations#create"
        post "company/forgot_password", to: "company_passwords#forgot"
        post "company/reset_password", to: "company_passwords#reset"
        post "reviewer/forgot_password", to: "reviewer_passwords#forgot"
        post "reviewer/reset_password", to: "reviewer_passwords#reset"
      end

      get "webhooks/whatsapp", to: "webhooks/whatsapp#verify"
      post "webhooks/whatsapp", to: "webhooks/whatsapp#create"
      post "webhooks/stripe", to: "webhooks/stripe#create"

      get "billing/mock_checkout", to: "billing/mock_checkout#show"

      namespace :internal do
        get "playbooks/active", to: "playbooks#active"
        get "knowledge/search", to: "knowledge#search"
        get "companies/:company_id/profile", to: "knowledge#profile"
        get "companies/:company_id/context_bundle", to: "knowledge#context_bundle"
        get "companies/:company_id/signals", to: "knowledge#signals"
        get "companies/:company_id/employee_summaries", to: "knowledge#employee_summaries"
        get "conversations/:conversation_id/excerpt", to: "knowledge#conversation_excerpt"
      end

      get "reviewer_users/:id/avatar", to: "reviewer_avatars#show"
      get "reviewer_users/:id/cv", to: "reviewer_cvs#show"

      namespace :platform do
        resources :companies, only: %i[index show create update]
        resources :playbooks, only: %i[index show create update] do
          member do
            post :activate
          end
        end
        get "trials", to: "trials#index"
        post "trials/:company_id/extend", to: "trials#extend"
        get "system", to: "system#show"
        resources :solutions, only: %i[index create update]
        get "companies/:company_id/question_feedback", to: "question_feedback#index"
        get "companies/:company_id/reports", to: "reports#index"
        post "companies/:company_id/reports", to: "reports#create"
        post "companies/:company_id/reports/:id/approve", to: "reports#approve"
        post "companies/:company_id/reports/:id/regenerate", to: "reports#regenerate"
        post "companies/:company_id/impersonate", to: "impersonations#create"
        get "monitoring", to: "monitoring#show"
        resources :agent_interrupts, only: %i[index update]
        resources :reviewers, only: %i[index show create update]
        get "companies/:company_id/reviewer_assignments", to: "reviewer_assignments#index"
        post "companies/:company_id/reviewer_assignments", to: "reviewer_assignments#create"
        delete "companies/:company_id/reviewer_assignments/:id", to: "reviewer_assignments#destroy"
        get "companies/:company_id/reviewer_chat", to: "reviewer_chat#index"
        post "companies/:company_id/reviewer_chat", to: "reviewer_chat#create"
        get "companies/:company_id/info_requests", to: "company_info_requests#index"
        post "companies/:company_id/info_requests", to: "company_info_requests#create"
        patch "companies/:company_id/info_requests/:id/close", to: "company_info_requests#close"
        get "companies/:company_id/documents", to: "company_documents#index"
        get "companies/:company_id/documents/:id/download", to: "company_documents#download"
      end

      namespace :reviewer do
        get "me", to: "me#show"
        get "followups", to: "followups#index"
        get "profile", to: "profile#show"
        patch "profile", to: "profile#update"
        post "profile/avatar", to: "profile#avatar"
        post "profile/cv", to: "profile#cv"
        resources :notifications, only: %i[index update] do
          collection do
            post :mark_all_read
          end
        end
        resources :companies, only: %i[index show] do
          resources :employees, only: %i[index show], controller: "employees"
          resources :conversations, only: %i[index show], controller: "conversations" do
            post "messages/:message_id/reprocess", to: "conversations#reprocess_message", on: :member
          end
          get "signals", to: "intelligence#signals"
          get "patterns", to: "intelligence#patterns"
          get "recommendations", to: "intelligence#recommendations"
          get "review_sync", to: "review_sync#show"
          resources :reports, only: %i[index show], controller: "reports" do
            resource :review, only: %i[show update], controller: "report_reviews" do
              post :submit, on: :member
              post :mark_ready, on: :member
              post :request_regeneration, on: :member
              resources :comments, only: %i[index create update destroy], controller: "report_review_comments"
              patch "section_states/:section_key", to: "report_review_section_states#update"
            end
          end
          resources :info_requests, only: %i[index create show], controller: "info_requests"
          post "employees/:employee_id/followup", to: "info_requests#create"
          get "employees/:employee_id/followup", to: "info_requests#thread"
          resources :chat_messages, only: %i[index create], controller: "chat_messages"
          get "profile_info_requests", to: "company_info_requests#index"
          post "profile_info_requests", to: "company_info_requests#create"
          patch "profile_info_requests/:id/close", to: "company_info_requests#close"
          get "documents", to: "documents#index"
          get "documents/:id/download", to: "documents#download"
          get "copilot", to: "copilot#index"
          post "copilot", to: "copilot#create"
          resources :agent_interrupts, only: %i[index update]
        end
      end

      namespace :company do
        get "me", to: "me#show"
        get "expert_reviewers", to: "expert_reviewers#index"
        get "onboarding", to: "onboarding#show"
        patch "onboarding/profile", to: "onboarding#update_profile"
        post "onboarding/complete", to: "onboarding#complete"
        get "setup_status", to: "setup_status#show"
        resources :info_requests, only: %i[index show], controller: "info_requests" do
          member do
            post "replies", action: :create_reply
          end
        end
        resources :documents, only: %i[index create] do
          member do
            get :download
          end
        end
        get "intelligence/snapshot", to: "intelligence#snapshot"
        get "intelligence/signals", to: "intelligence#signals"
        get "intelligence/patterns", to: "intelligence#patterns"
        get "intelligence/timeline", to: "intelligence#timeline"
        get "discovery_questions", to: "discovery_questions#index"
        post "discovery_questions/:id/feedback", to: "discovery_questions#feedback"
        resources :recommendations, only: %i[index] do
          member do
            patch :feedback, action: :update_feedback
          end
        end
        resources :reports, only: %i[index show create] do
          member do
            get :download
            post :share
          end
        end
        get "settings/organization", to: "settings#organization"
        patch "settings/organization", to: "settings#update_organization"
        get "settings/security", to: "settings#security"
        post "settings/security/rotate_codes", to: "settings#rotate_access_codes"
        resources :notifications, only: %i[index update] do
          collection do
            post :mark_all_read
          end
        end
        get "billing", to: "billing#show"
        post "billing/checkout", to: "billing#checkout"
        resources :employees, only: %i[index show create] do
          member do
            post :nudge
            patch :phone, action: :update_phone
          end
          collection do
            post :bulk_create
          end
        end
      end

      namespace :public do
        get "reports/:token", to: "reports#show"
      end
    end
  end
end
