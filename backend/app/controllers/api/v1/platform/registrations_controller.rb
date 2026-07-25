# frozen_string_literal: true

module Api
  module V1
    module Platform
      class RegistrationsController < BaseController
        def index
          company_regs = CompanyRegistration.includes(:company, :company_user).order(created_at: :desc)
          company_regs = company_regs.where(status: params[:status]) if params[:status].present?

          reviewers = ReviewerUser.pending_applications.order(created_at: :desc)

          render json: {
            company_registrations: company_regs.map { |r| company_registration_json(r) },
            reviewer_applications: reviewers.map { |r| reviewer_application_json(r) }
          }
        end

        def approve_company
          registration = CompanyRegistration.find(params[:id])
          result = Registrations::ApproveCompanyRegistration.call(
            registration: registration,
            platform_user: current_platform_user,
            review_note: params[:review_note]
          )
          PlatformAuditService.log!(
            platform_user: current_platform_user,
            action: "company_registration_approved",
            target: result.company,
            metadata: { registration_id: result.id },
            request: request
          )
          render json: { company_registration: company_registration_json(result) }
        rescue Registrations::ApproveCompanyRegistration::Error => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        def reject_company
          registration = CompanyRegistration.find(params[:id])
          result = Registrations::RejectCompanyRegistration.call(
            registration: registration,
            platform_user: current_platform_user,
            review_note: params[:review_note]
          )
          PlatformAuditService.log!(
            platform_user: current_platform_user,
            action: "company_registration_rejected",
            target: result.company,
            metadata: { registration_id: result.id },
            request: request
          )
          render json: { company_registration: company_registration_json(result) }
        rescue Registrations::RejectCompanyRegistration::Error => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        def approve_reviewer
          reviewer = ReviewerUser.find(params[:id])
          result = Registrations::ApproveReviewerApplication.call(
            reviewer: reviewer,
            platform_user: current_platform_user,
            review_note: params[:review_note]
          )
          PlatformAuditService.log!(
            platform_user: current_platform_user,
            action: "reviewer_application_approved",
            target: result,
            request: request
          )
          render json: { reviewer_application: reviewer_application_json(result) }
        rescue Registrations::ApproveReviewerApplication::Error => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        def reject_reviewer
          reviewer = ReviewerUser.find(params[:id])
          result = Registrations::RejectReviewerApplication.call(
            reviewer: reviewer,
            platform_user: current_platform_user,
            review_note: params[:review_note]
          )
          PlatformAuditService.log!(
            platform_user: current_platform_user,
            action: "reviewer_application_rejected",
            target: result,
            request: request
          )
          render json: { reviewer_application: reviewer_application_json(result) }
        rescue Registrations::RejectReviewerApplication::Error => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        private

        def company_registration_json(registration)
          {
            id: registration.id,
            status: registration.status,
            company_name: registration.company_name,
            admin_name: registration.admin_name,
            admin_email: registration.admin_email,
            admin_phone: registration.admin_phone,
            role_title: registration.role_title,
            notes: registration.notes,
            review_note: registration.review_note,
            company_id: registration.company_id,
            company_approval_status: registration.company.approval_status,
            admin_user_status: registration.company_user.status,
            company_profile: registration.company.company_profile,
            engagement_mode: registration.company.engagement_mode,
            created_at: registration.created_at,
            reviewed_at: registration.reviewed_at
          }
        end

        def reviewer_application_json(reviewer)
          {
            id: reviewer.id,
            status: reviewer.status,
            name: reviewer.name,
            email: reviewer.email,
            headline: reviewer.headline,
            expertise_summary: reviewer.expertise_summary,
            application_notes: reviewer.application_notes,
            approved_at: reviewer.approved_at,
            rejected_at: reviewer.rejected_at,
            created_at: reviewer.created_at
          }
        end
      end
    end
  end
end
