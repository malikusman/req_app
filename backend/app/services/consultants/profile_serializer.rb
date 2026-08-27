# frozen_string_literal: true

module Consultants
  module ProfileSerializer
    module_function

    def public_card(consultant, request: nil)
      {
        id: consultant.id,
        name: consultant.name,
        headline: consultant.headline,
        bio: consultant.bio,
        avatar_url: avatar_path(consultant, request),
        expertise_tags: consultant.expertise_tags,
        industries: consultant.industries,
        years_experience: consultant.years_experience,
        languages: consultant.languages,
        location: consultant.location,
        linkedin_url: consultant.linkedin_url,
        profile_status: consultant.profile_status,
        platform_verified: consultant.platform_verified_at.present?,
        experiences: consultant.consultant_experiences.order(:sort_order, :start_year).map { |e| experience_json(e) }
      }
    end

    def full(consultant, request: nil, include_account: false)
      completeness = Consultants::ProfileCompleteness.call(consultant)
      progress = Consultants::QuestionnaireProgress.call(consultant.questionnaire_answers, consultant: consultant)
      verification_signals = consultant.cv_storage_key.present?

      json = {
        headline: consultant.headline,
        bio: consultant.bio,
        linkedin_url: consultant.linkedin_url,
        website_url: consultant.website_url,
        location: consultant.location,
        timezone: consultant.timezone,
        languages: consultant.languages,
        expertise_tags: consultant.expertise_tags,
        industries: consultant.industries,
        years_experience: consultant.years_experience,
        credentials: consultant.credentials,
        profile_status: consultant.profile_status,
        profile_completed_at: consultant.profile_completed_at,
        platform_verified_at: consultant.platform_verified_at,
        avatar_url: avatar_path(consultant, request),
        cv_url: cv_path(consultant, request),
        has_cv: consultant.cv_storage_key.present?,
        verification_signals: verification_signals,
        experiences: consultant.consultant_experiences.order(:sort_order, :start_year).map { |e| experience_json(e) },
        completeness: {
          percent: completeness.percent,
          complete: completeness.complete,
          missing: completeness.missing,
          checks: completeness.checks,
          questionnaire_percent: progress[:completion_percent]
        },
        suggested_expertise_tags: Consultants::ExpertiseCatalog::SUGGESTED
      }
      if include_account
        json.merge!(
          id: consultant.id,
          email: consultant.email,
          name: consultant.name,
          status: consultant.status
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

    def avatar_path(consultant, request = nil)
      return nil if consultant.avatar_storage_key.blank?

      "/api/v1/consultant_users/#{consultant.id}/avatar"
    end

    def cv_path(consultant, request = nil)
      return nil if consultant.cv_storage_key.blank?

      "/api/v1/consultant/profile/cv"
    end
  end
end
