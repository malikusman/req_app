# frozen_string_literal: true

module Api
  module V1
    module Platform
      class RegistrationsController < BaseController
        def index
          company_regs = CompanyRegistration.includes(:company, :company_user).order(created_at: :desc)
          company_regs = company_regs.where(status: params[:status]) if params[:status].present?

          consultants = ConsultantUser.pending_applications.order(created_at: :desc)

          render json: {
            company_registrations: company_regs.map { |r| company_registration_json(r) },
            consultant_applications: consultants.map { |r| consultant_application_json(r) }
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

        def approve_consultant
          consultant = ConsultantUser.find(params[:id])
          result = Registrations::ApproveConsultantApplication.call(
            consultant: consultant,
            platform_user: current_platform_user,
            review_note: params[:review_note]
          )
          PlatformAuditService.log!(
            platform_user: current_platform_user,
            action: "consultant_application_approved",
            target: result,
            request: request
          )
          render json: { consultant_application: consultant_application_json(result) }
        rescue Registrations::ApproveConsultantApplication::Error => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        def reject_consultant
          consultant = ConsultantUser.find(params[:id])
          result = Registrations::RejectConsultantApplication.call(
            consultant: consultant,
            platform_user: current_platform_user,
            review_note: params[:review_note]
          )
          PlatformAuditService.log!(
            platform_user: current_platform_user,
            action: "consultant_application_rejected",
            target: result,
            request: request
          )
          render json: { consultant_application: consultant_application_json(result) }
        rescue Registrations::RejectConsultantApplication::Error => e
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

        def consultant_application_json(consultant)
          {
            id: consultant.id,
            status: consultant.status,
            name: consultant.name,
            email: consultant.email,
            headline: consultant.headline,
            expertise_summary: consultant.expertise_summary,
            application_notes: consultant.application_notes,
            approved_at: consultant.approved_at,
            rejected_at: consultant.rejected_at,
            created_at: consultant.created_at
          }
        end
      end
    end
  end
end
