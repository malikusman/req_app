# frozen_string_literal: true

module Reviewers
  class UpdateProfileService
    def self.call(reviewer:, params:, experiences: nil, publish: nil)
      new(reviewer: reviewer, params: params, experiences: experiences, publish: publish).call
    end

    def initialize(reviewer:, params:, experiences: nil, publish: nil)
      @reviewer = reviewer
      @params = params
      @experiences = experiences
      @publish = publish
    end

    def call
      ActiveRecord::Base.transaction do
        @reviewer.update!(@params) if @params.present?
        sync_experiences! if @experiences
        @reviewer.reload
        sync_completion_timestamp!

        if @publish == true
          result = Reviewers::ProfileCompleteness.call(@reviewer)
          raise ArgumentError, "Profile incomplete: #{result.missing.join(', ')}" unless result.complete

          @reviewer.update!(
            profile_status: "pending_review",
            profile_completed_at: Time.current,
            platform_verified_at: nil
          )
        elsif @publish == false
          @reviewer.update!(profile_status: "draft")
        end
      end
    end

    def sync_completion_timestamp!
      result = Reviewers::ProfileCompleteness.call(@reviewer)
      @reviewer.update!(
        profile_completed_at: result.complete ? (@reviewer.profile_completed_at || Time.current) : nil
      )
    end

    private

    def sync_experiences!
      @reviewer.reviewer_experiences.destroy_all
      Array(@experiences).each_with_index do |attrs, index|
        @reviewer.reviewer_experiences.create!(
          organization: attrs[:organization] || attrs["organization"],
          title: attrs[:title] || attrs["title"],
          start_year: attrs[:start_year] || attrs["start_year"],
          end_year: attrs[:end_year] || attrs["end_year"],
          summary: attrs[:summary] || attrs["summary"],
          sort_order: attrs[:sort_order] || index
        )
      end
    end
  end
end
