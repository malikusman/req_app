# frozen_string_literal: true

module Engagements
  # Mjadi sets up a client engagement (Doc 07 §3, S1–S8): the company, the
  # engagement and the key user's account, with the lead consultant assigned.
  # There is no trial and no password chosen for the client — the key user is
  # invited to set their own.
  #
  # Also used to approve a sign-up request, in which case the company and the
  # key user already exist and only the engagement details are added.
  class Create
    class Error < StandardError; end

    LANGUAGE_FORMAT = /\A[a-z]{2}\z/

    def self.call(platform_user:, params:, company: nil, key_user: nil, request: nil)
      new(platform_user: platform_user, params: params, company: company, key_user: key_user, request: request).call
    end

    def initialize(platform_user:, params:, company:, key_user:, request:)
      @platform_user = platform_user
      @params = params.to_h.deep_stringify_keys
      @company = company
      @key_user = key_user
      @request = request
    end

    def call
      validate!
      engagement = nil
      ActiveRecord::Base.transaction do
        company = @company || create_company!
        company.update!(approval_status: "approved", approved_at: company.approved_at || Time.current,
                        rejected_at: nil, website_url: website_url || company.website_url)
        key_user = @key_user || create_key_user!(company)
        key_user.update!(job_title: key_user_param("role_title")) if key_user_param("role_title")
        engagement = company.engagements.create!(
          status: "SET_UP",
          status_history: [{ "from" => nil, "to" => "SET_UP", "at" => Time.current.iso8601,
                             "by_type" => @platform_user.class.name, "by_id" => @platform_user.id }],
          scope_type: scope_type,
          departments_in_scope: departments,
          key_user: key_user,
          lead_consultant: lead_consultant,
          languages: languages,
          proposal_reference: @params["proposal_reference"].to_s.strip.presence
        )
        assign_lead_consultant!(company)
      end

      PlatformAuditService.log!(platform_user: @platform_user, action: "engagement_created", target: engagement,
                                metadata: { company_id: engagement.company_id, scope_type: engagement.scope_type },
                                request: @request)
      Engagements::Invite.call(engagement: engagement)
      # Read the website now, so the proposals are ready when the key user first signs in.
      WebsitePrefillJob.start(engagement)
      engagement
    rescue ActiveRecord::RecordInvalid => e
      raise Error, e.record.errors.full_messages.to_sentence
    end

    private

    def validate!
      raise Error, "Company name is required" if @company.nil? && @params["company_name"].to_s.strip.blank?
      unless Engagement::SCOPE_TYPES.include?(scope_type)
        raise Error, "Scope must be the whole company or named departments"
      end
      if scope_type == "DEPARTMENT" && departments.empty?
        raise Error, "Name the departments in scope for a department engagement"
      end
      raise Error, "Choose at least one engagement language" if languages.empty?
      raise Error, "Choose a lead consultant" unless lead_consultant

      validate_new_key_user! unless @key_user
    end

    def validate_new_key_user!
      raise Error, "The key user's name is required" if key_user_param("name").blank?
      raise Error, "A valid email is required for the key user" unless key_user_email.match?(URI::MailTo::EMAIL_REGEXP)

      taken = [CompanyUser, ConsultantUser, PlatformUser].any? { |model| model.exists?(email: key_user_email) } ||
              CompanyRegistration.pending.exists?(admin_email: key_user_email)
      raise Error, "An account with this email already exists" if taken
    end

    def create_company!
      name = @params["company_name"].to_s.strip
      ::Company.create!(name: name, display_name: name, locale: languages.first)
    end

    def create_key_user!(company)
      company.company_users.create!(
        email: key_user_email,
        name: key_user_param("name"),
        phone: key_user_param("phone"),
        role: "company_admin",
        status: "pending",
        # Never used: the key user chooses their own password from the invitation.
        password: SecureRandom.base58(32)
      )
    end

    def assign_lead_consultant!(company)
      return if company.consultant_assignments.active.exists?(consultant_user_id: lead_consultant.id)

      ConsultantAssignments::AssignService.call(company: company, consultant_user: lead_consultant,
                                                platform_user: @platform_user, request: @request)
    rescue ArgumentError => e
      raise Error, e.message
    end

    def scope_type
      @params["scope_type"].to_s.upcase.presence || "COMPANY"
    end

    def departments
      Array(@params["departments_in_scope"]).map { |d| d.to_s.strip }.reject(&:blank?).uniq.first(30)
    end

    def languages
      Array(@params["languages"]).map { |l| l.to_s.strip.downcase }.select { |l| l.match?(LANGUAGE_FORMAT) }.uniq
    end

    def lead_consultant
      @lead_consultant ||= ConsultantUser.find_by(id: @params["lead_consultant_id"], status: "active")
    end

    def website_url
      url = @params["website_url"].to_s.strip.presence
      return nil unless url

      url.match?(%r{\Ahttps?://}i) ? url : "https://#{url}"
    end

    def key_user_param(key)
      @params.dig("key_user", key).to_s.strip.presence
    end

    def key_user_email
      key_user_param("email").to_s.downcase
    end
  end
end
