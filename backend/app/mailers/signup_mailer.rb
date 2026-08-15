# frozen_string_literal: true

require "cgi"

class SignupMailer < ApplicationMailer
  default from: -> { ENV.fetch("FROM_EMAIL", "from@example.com") }

  def company_registration_received(registration)
    @registration = registration
    mail(to: registration.admin_email, subject: "We received your Worktruth signup request")
  end

  def company_registration_admin_notice(registration)
    @registration = registration
    mail(
      to: admin_inbox,
      subject: "Company signup pending — #{registration.company_name}"
    )
  end

  def company_registration_approved(registration, token)
    @registration = registration
    @set_password_url = set_password_url(token, portal: "company")
    mail(to: registration.admin_email, subject: "Your Worktruth company account is approved")
  end

  def company_registration_rejected(registration)
    @registration = registration
    mail(to: registration.admin_email, subject: "Update on your Worktruth signup request")
  end

  def reviewer_application_received(reviewer)
    @reviewer = reviewer
    mail(to: reviewer.email, subject: "We received your Worktruth reviewer application")
  end

  def reviewer_application_admin_notice(reviewer)
    @reviewer = reviewer
    mail(to: admin_inbox, subject: "Reviewer application pending — #{reviewer.name}")
  end

  def reviewer_application_approved(reviewer, token)
    @reviewer = reviewer
    @set_password_url = set_password_url(token, portal: "reviewer")
    mail(to: reviewer.email, subject: "Your Worktruth reviewer account is approved")
  end

  def reviewer_application_rejected(reviewer)
    @reviewer = reviewer
    mail(to: reviewer.email, subject: "Update on your Worktruth reviewer application")
  end

  def password_reset(user, token, portal)
    @user = user
    @portal = portal
    @set_password_url = set_password_url(token, portal: portal)
    mail(to: user.email, subject: "Reset your Worktruth password")
  end

  def company_admin_credentials(user, password)
    @user = user
    @password = password
    @login_url = portal_login_url("company")
    company_name = user.company&.display_name.presence || user.company&.name || "your company"
    mail(to: user.email, subject: "Your Worktruth login for #{company_name}")
  end

  private

  def admin_inbox
    ENV.fetch("SALES_INBOX", "sales@worktruth.com")
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
