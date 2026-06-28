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
      end

      get "webhooks/whatsapp", to: "webhooks/whatsapp#verify"
      post "webhooks/whatsapp", to: "webhooks/whatsapp#create"
      post "webhooks/stripe", to: "webhooks/stripe#create"

      get "billing/mock_checkout", to: "billing/mock_checkout#show"

      namespace :internal do
        get "playbooks/active", to: "playbooks#active"
      end

      get "reviewer_users/:id/avatar", to: "reviewer_avatars#show"

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
        get "companies/:company_id/conversations", to: "conversations#index"
        get "companies/:company_id/conversations/:id", to: "conversations#show"
        get "companies/:company_id/media_attachments/:id/download", to: "media_attachments#download"
        get "companies/:company_id/intelligence/snapshot", to: "intelligence#snapshot"
        get "companies/:company_id/intelligence/signals", to: "intelligence#signals"
        get "companies/:company_id/intelligence/patterns", to: "intelligence#patterns"
        get "companies/:company_id/intelligence/recommendations", to: "intelligence#recommendations"
        get "companies/:company_id/intelligence/timeline", to: "intelligence#timeline"
        post "companies/:company_id/reports/:id/approve", to: "reports#approve"
        get "companies/:company_id/reports/:id/download", to: "reports#download"
        post "companies/:company_id/impersonate", to: "impersonations#create"
        get "monitoring", to: "monitoring#show"
        get "dashboard", to: "dashboard#show"
        get "audit_logs", to: "audit_logs#index"
        resources :reviewers, only: %i[index show create update]
        get "companies/:company_id/reviewer_assignments", to: "reviewer_assignments#index"
        post "companies/:company_id/reviewer_assignments", to: "reviewer_assignments#create"
        delete "companies/:company_id/reviewer_assignments/:id", to: "reviewer_assignments#destroy"
        get "companies/:company_id/reviewer_chat", to: "reviewer_chat#index"
      end

      namespace :reviewer do
        get "me", to: "me#show"
        get "dashboard", to: "dashboard#show"
        get "followups", to: "followups#index"
        get "profile", to: "profile#show"
        patch "profile", to: "profile#update"
        post "profile/avatar", to: "profile#avatar"
        resources :notifications, only: %i[index update] do
          collection do
            post :mark_all_read
          end
        end
        resources :companies, only: %i[index show] do
          resources :employees, only: %i[index show], controller: "employees"
          resources :conversations, only: %i[index show], controller: "conversations"
          get "signals", to: "intelligence#signals"
          get "patterns", to: "intelligence#patterns"
          get "recommendations", to: "intelligence#recommendations"
          get "review_sync", to: "review_sync#show"
          resources :reports, only: %i[index show], controller: "reports" do
            member do
              get :download
            end
            resource :review, only: %i[show update], controller: "report_reviews" do
              post :submit, on: :member
              resources :comments, only: %i[index create update destroy], controller: "report_review_comments"
              patch "section_states/:section_key", to: "report_review_section_states#update"
            end
          end
          resources :info_requests, only: %i[index create show], controller: "info_requests"
          post "employees/:employee_id/followup", to: "info_requests#create"
          get "employees/:employee_id/followup", to: "info_requests#thread"
          resources :chat_messages, only: %i[index create], controller: "chat_messages"
          get "media_attachments", to: "media_attachments#index"
          get "media_attachments/:id/download", to: "media_attachments#download"
        end
      end

      namespace :company do
        get "me", to: "me#show"
        get "dashboard", to: "dashboard#show"
        get "expert_reviewers", to: "expert_reviewers#index"
        get "onboarding", to: "onboarding#show"
        patch "onboarding/profile", to: "onboarding#update_profile"
        post "onboarding/complete", to: "onboarding#complete"
        resources :documents, only: %i[index create]
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
        resources :conversations, only: %i[index show]
        get "media_attachments", to: "media_attachments#index"
        get "media_attachments/:id/download", to: "media_attachments#download"
      end

      namespace :public do
        get "reports/:token", to: "reports#show"
        get "discover/sessions/:token", to: "discover_sessions#show"
        post "discover/sessions/:token/verify", to: "discover_verifications#create"
        get "discover/messages", to: "discover_messages#index"
        post "discover/messages", to: "discover_messages#create"
        post "discover/attachments", to: "discover_attachments#create"
      end
    end
  end
end
