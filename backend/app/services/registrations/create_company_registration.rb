# frozen_string_literal: true

module Registrations
  class CreateCompanyRegistration
    class Error < StandardError; end

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(
      company_name:,
      admin_name:,
      admin_email:,
      role_title: nil,
      notes: nil,
      display_name: nil,
      engagement_mode: nil,
      company_profile: nil,
      known_systems: nil
    )
      @company_name = company_name.to_s.strip
      @display_name = display_name.to_s.strip.presence || @company_name
      @admin_name = admin_name.to_s.strip
      @admin_email = admin_email.to_s.strip.downcase
      @role_title = role_title.to_s.strip.presence
      @notes = notes.to_s.strip.presence
      @engagement_mode = engagement_mode.to_s.strip.presence
      @company_profile = company_profile
      @known_systems = known_systems
    end

    def call
      validate!

      registration = nil
      ActiveRecord::Base.transaction do
        settings = {}
        if @engagement_mode.present?
          mode = Company::ENGAGEMENT_MODES.include?(@engagement_mode) ? @engagement_mode : "hybrid"
          settings["engagement_mode"] = mode
        end

        company = Company.create!(
          name: @company_name,
          display_name: @display_name,
          approval_status: "pending_approval",
          settings: settings
        )
        user = CompanyUser.create!(
          company: company,
          email: @admin_email,
          name: @admin_name,
          role: "company_admin",
          status: "pending",
          password: SecureRandom.hex(24)
        )
        registration = CompanyRegistration.create!(
          company: company,
          company_user: user,
          company_name: @company_name,
          admin_name: @admin_name,
          admin_email: @admin_email,
          role_title: @role_title,
          notes: @notes,
          status: "pending"
        )

        if @company_profile.present? || !@known_systems.nil?
          Companies::ProfileUpdater.call(
            company: company,
            profile_params: (@company_profile || {}).to_h,
            known_systems: @known_systems
          )
        end
      end

      SignupMailer.company_registration_received(registration).deliver_later
      SignupMailer.company_registration_admin_notice(registration).deliver_later
      registration
    end

    private

    def validate!
      raise Error, "Company name is required" if @company_name.blank?
      raise Error, "Your name is required" if @admin_name.blank?
      raise Error, "A valid work email is required" unless @admin_email.match?(URI::MailTo::EMAIL_REGEXP)
      if CompanyUser.exists?(email: @admin_email) || CompanyRegistration.pending.exists?(admin_email: @admin_email)
        raise Error, "An account with this email already exists or is pending approval"
      end
      if ReviewerUser.exists?(email: @admin_email) || PlatformUser.exists?(email: @admin_email)
        raise Error, "An account with this email already exists"
      end
    end
  end
end
