# frozen_string_literal: true

module Reviewers
  module ProfileSerializer
    module_function

    def public_card(reviewer, request: nil)
      {
        id: reviewer.id,
        name: reviewer.name,
        headline: reviewer.headline,
        avatar_url: avatar_path(reviewer, request),
        expertise_tags: reviewer.expertise_tags,
        industries: reviewer.industries,
        years_experience: reviewer.years_experience,
        languages: reviewer.languages,
        location: reviewer.location,
        linkedin_url: reviewer.linkedin_url,
        profile_status: reviewer.profile_status,
        platform_verified: reviewer.platform_verified_at.present?
      }
    end

    def full(reviewer, request: nil, include_account: false)
      completeness = Reviewers::ProfileCompleteness.call(reviewer)
      json = {
        headline: reviewer.headline,
        bio: reviewer.bio,
        linkedin_url: reviewer.linkedin_url,
        website_url: reviewer.website_url,
        location: reviewer.location,
        timezone: reviewer.timezone,
        languages: reviewer.languages,
        expertise_tags: reviewer.expertise_tags,
        industries: reviewer.industries,
        years_experience: reviewer.years_experience,
        credentials: reviewer.credentials,
        profile_status: reviewer.profile_status,
        profile_completed_at: reviewer.profile_completed_at,
        platform_verified_at: reviewer.platform_verified_at,
        avatar_url: avatar_path(reviewer, request),
        cv_url: cv_path(reviewer, request),
        cv_filename: reviewer.cv_filename,
        experiences: reviewer.reviewer_experiences.order(:sort_order, :start_year).map { |e| experience_json(e) },
        completeness: {
          percent: completeness.percent,
          complete: completeness.complete,
          missing: completeness.missing,
          checks: completeness.checks
        },
        suggested_expertise_tags: Reviewers::ExpertiseCatalog::SUGGESTED
      }
      if include_account
        json.merge!(
          id: reviewer.id,
          email: reviewer.email,
          name: reviewer.name,
          status: reviewer.status
        )
      end
      json
    end

    def experience_json(experience)
      {
        id: experience.id,
        organization: experience.organization,
        title: experience.title,
        start_year: experience.start_year,
        end_year: experience.end_year,
        summary: experience.summary,
        sort_order: experience.sort_order
      }
    end

    def avatar_path(reviewer, request)
      return nil if reviewer.avatar_storage_key.blank? || request.nil?

      "#{request.base_url}/api/v1/reviewer_users/#{reviewer.id}/avatar"
    end

    def cv_path(reviewer, request)
      return nil if reviewer.cv_storage_key.blank? || request.nil?

      "#{request.base_url}/api/v1/reviewer_users/#{reviewer.id}/cv"
    end
  end
end
