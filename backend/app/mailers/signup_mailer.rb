# frozen_string_literal: true

require "cgi"

class SignupMailer < ApplicationMailer
  default from: -> { ENV.fetch("FROM_EMAIL", "from@example.com") }

  def company_registration_received(registration)
    @registration = registration
    mail(to: registration.admin_email, subject: "We received your Mjadi signup request")
  end

  def company_registration_admin_notice(registration)
    @registration = registration
    mail(
      to: admin_inbox,
      subject: "Company signup pending — #{registration.company_name}"
    )
  end

  def company_registration_rejected(registration)
    @registration = registration
    mail(to: registration.admin_email, subject: "Update on your Mjadi signup request")
  end

  def consultant_application_received(consultant)
    @consultant = consultant
    mail(to: consultant.email, subject: "We received your Mjadi consultant application")
  end

  def consultant_application_admin_notice(consultant)
    @consultant = consultant
    mail(to: admin_inbox, subject: "Consultant application pending — #{consultant.name}")
  end

  def consultant_application_approved(consultant, token)
    @consultant = consultant
    @set_password_url = set_password_url(token, portal: "consultant")
    mail(to: consultant.email, subject: "Your Mjadi consultant account is approved")
  end

  def consultant_application_rejected(consultant)
    @consultant = consultant
    mail(to: consultant.email, subject: "Update on your Mjadi consultant application")
  end

  def password_reset(user, token, portal)
    @user = user
    @portal = portal
    @set_password_url = set_password_url(token, portal: portal)
    mail(to: user.email, subject: "Reset your Mjadi password")
  end

  # The key user's invitation to an engagement Mjadi has set up (Doc 07 §3).
  def engagement_invitation(engagement, token)
    @user = engagement.key_user
    @company_name = engagement.company.display_name.presence || engagement.company.name
    @consultant_name = engagement.lead_consultant&.name
    @has_website = engagement.company.website_url.present?
    @set_password_url = set_password_url(token, portal: "company")
    mail(to: @user.email, subject: "Your Mjadi engagement with #{@company_name} is ready")
  end

  private

  def admin_inbox
    ENV.fetch("SALES_INBOX", "sales@mjadi.com")
  end

  def set_password_url(token, portal:)
    host = ENV.fetch("APP_HOST", "http://localhost:5173").chomp("/")
    "#{host}/auth/set-password?token=#{CGI.escape(token)}&portal=#{CGI.escape(portal)}"
  end

  def portal_login_url(portal)
    host = ENV.fetch("APP_HOST", "http://localhost:5173").chomp("/")
    "#{host}/#{portal}/login"
  end
end
