# frozen_string_literal: true

Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  get "health/ready", to: "health#ready"
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
        get "catalog/sources", to: "catalog_sources#index"
        post "catalog/sources", to: "catalog_sources#create"
        patch "catalog/sources/:id", to: "catalog_sources#update"
        delete "catalog/sources/:id", to: "catalog_sources#destroy"
        post "catalog/sources/:id/sync", to: "catalog_sources#sync"
        post "catalog/sources/seed_recommended", to: "catalog_sources#seed_recommended"
        get "catalog/candidates", to: "catalog_candidates#index"
        get "catalog/candidates/:id", to: "catalog_candidates#show"
        post "catalog/candidates/:id/approve", to: "catalog_candidates#approve"
        post "catalog/candidates/:id/reject", to: "catalog_candidates#reject"
        post "catalog/candidates/:id/merge", to: "catalog_candidates#merge"
        post "catalog/sync", to: "catalog_sync#create"
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
        get "companies/:company_id/company_systems", to: "company_systems#index"
        post "companies/:company_id/company_systems", to: "company_systems#create"
        patch "companies/:company_id/company_systems/:id", to: "company_systems#update"
        delete "companies/:company_id/company_systems/:id", to: "company_systems#destroy"
        post "companies/:company_id/company_systems/infer", to: "company_systems#infer"
        get "companies/:company_id/agentic_ideas", to: "agentic_ideas#index"
        post "companies/:company_id/agentic_ideas", to: "agentic_ideas#create"
        patch "companies/:company_id/agentic_ideas/:id", to: "agentic_ideas#update"
        post "companies/:company_id/agentic_ideas/:id/publish", to: "agentic_ideas#publish"
        post "companies/:company_id/agentic_ideas/:id/archive", to: "agentic_ideas#archive"
        post "companies/:company_id/agentic_ideas/synthesize", to: "agentic_ideas#synthesize"
        post "companies/:company_id/reports/:id/approve", to: "reports#approve"
        get "companies/:company_id/reports/:id/download", to: "reports#download"
        post "companies/:company_id/impersonate", to: "impersonations#create"
        get "monitoring", to: "monitoring#show"
        get "dashboard", to: "dashboard#show"
        get "audit_logs", to: "audit_logs#index"
        get "registrations", to: "registrations#index"
        post "registrations/companies/:id/approve", to: "registrations#approve_company"
        post "registrations/companies/:id/reject", to: "registrations#reject_company"
        post "registrations/reviewers/:id/approve", to: "registrations#approve_reviewer"
        post "registrations/reviewers/:id/reject", to: "registrations#reject_reviewer"
        resources :reviewers, only: %i[index show create update] do
          member do
            get :cv
          end
        end
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
        patch "profile/questionnaire", to: "profile#update_questionnaire"
        post "profile/avatar", to: "profile#avatar"
        post "profile/cv", to: "profile#cv"
        get "profile/cv", to: "profile#show_cv"
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
              get :workspace, to: "review_workspace#show"
            end
            resources :discussions, only: %i[index create], controller: "review_discussions" do
              member do
                post :reply
                patch :resolve
              end
            end
            resource :review, only: %i[show update], controller: "report_reviews" do
              post :submit, on: :member
              resources :comments, only: %i[index create update destroy], controller: "report_review_comments"
              resources :findings, only: %i[index create update destroy], controller: "report_review_findings"
              patch "section_states/:section_key", to: "report_review_section_states#update"
            end
          end
          resources :info_requests, only: %i[index create show], controller: "info_requests"
          post "employees/:employee_id/followup", to: "info_requests#create"
          get "employees/:employee_id/followup", to: "info_requests#thread"
          resources :chat_messages, only: %i[index create], controller: "chat_messages"
          get "media_attachments", to: "media_attachments#index"
          get "media_attachments/:id/download", to: "media_attachments#download"
          get "documents", to: "documents#index"
          get "documents/:id", to: "documents#show"
          get "documents/:id/download", to: "documents#download"
          get "document_analysis", to: "document_analysis#show"
          post "clarification_questions/:id/dismiss", to: "document_analysis#dismiss_question"
          resources :outreaches, only: %i[index create show], controller: "outreaches"
          get "catalog", to: "catalog#index"
          post "catalog/:id/endorse", to: "catalog#endorse"
          resources :agentic_ideas, only: %i[index create update], controller: "agentic_ideas" do
            member do
              post :publish
            end
          end
        end
      end

      namespace :company do
        get "me", to: "me#show"
        get "dashboard", to: "dashboard#show"
        get "expert_reviewers", to: "expert_reviewers#index"
        get "onboarding", to: "onboarding#show"
        patch "onboarding/profile", to: "onboarding#update_profile"
        patch "onboarding/questionnaire", to: "onboarding#update_questionnaire"
        post "onboarding/complete", to: "onboarding#complete"
        resources :documents, only: %i[index show create update destroy] do
          member do
            get :download
            post :replace
          end
        end
        resources :document_analysis_runs, only: %i[index show create]
        resources :knowledge_entries, only: %i[index]
        resources :clarification_questions, only: %i[index] do
          member do
            post :answer
          end
        end
        resources :outreaches, only: %i[index show], controller: "outreaches" do
          member do
            post :approve
            post :decline
            post :answer
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
        resources :agentic_ideas, only: %i[index], controller: "agentic_ideas"
        resources :reports, only: %i[index show create] do
          member do
            get :download
            post :share
          end
        end
        get "settings/organization", to: "settings#organization"
        patch "settings/organization", to: "settings#update_organization"
        post "settings/organization/web_research", to: "settings#refresh_web_research"
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
            post :reissue_access_code
          end
          collection do
            post :bulk_create
          end
          resource :value_preference, only: %i[show update], controller: "employee_value_preferences" do
            post :generate_digest
            post :send_digest
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
        get "outreach/:token", to: "outreach_replies#show"
        post "outreach/:token/reply", to: "outreach_replies#create"
        post "demo_requests", to: "demo_requests#create"
        post "company_registrations", to: "company_registrations#create"
        post "reviewer_applications", to: "reviewer_applications#create"
        post "password_resets", to: "password_resets#create"
        get "password_resets/verify", to: "password_resets#show"
        put "password_resets/confirm", to: "password_resets#update"
        patch "password_resets/confirm", to: "password_resets#update"
      end
    end
  end
end
