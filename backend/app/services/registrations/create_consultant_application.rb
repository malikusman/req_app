# frozen_string_literal: true

module Registrations
  class CreateConsultantApplication
    class Error < StandardError; end

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(name:, email:, notes: nil, expertise_summary: nil, headline: nil)
      @name = name.to_s.strip
      @email = email.to_s.strip.downcase
      @notes = notes.to_s.strip.presence
      @expertise_summary = expertise_summary.to_s.strip.presence
      @headline = headline.to_s.strip.presence
    end

    def call
      validate!

      consultant = ConsultantUser.create!(
        name: @name,
        email: @email,
        status: "pending",
        password: SecureRandom.hex(24),
        application_notes: @notes,
        expertise_summary: @expertise_summary,
        headline: @headline
      )

      SignupMailer.consultant_application_received(consultant).deliver_later
      SignupMailer.consultant_application_admin_notice(consultant).deliver_later
      consultant
    end

    private

    def validate!
      raise Error, "Name is required" if @name.blank?
      raise Error, "A valid email is required" unless @email.match?(URI::MailTo::EMAIL_REGEXP)
      if ConsultantUser.exists?(email: @email) || CompanyUser.exists?(email: @email) || PlatformUser.exists?(email: @email)
        raise Error, "An account with this email already exists or is pending approval"
      end
    end
  end
end
