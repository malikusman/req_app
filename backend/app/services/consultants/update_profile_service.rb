# frozen_string_literal: true

module Consultants
  class UpdateProfileService
    def self.call(consultant:, params:, experiences: nil, publish: nil)
      new(consultant: consultant, params: params, experiences: experiences, publish: publish).call
    end

    def initialize(consultant:, params:, experiences: nil, publish: nil)
      @consultant = consultant
      @params = params
      @experiences = experiences
      @publish = publish
    end

    def call
      ActiveRecord::Base.transaction do
        @consultant.update!(@params) if @params.present?
        sync_experiences! if @experiences
        @consultant.reload
        sync_completion_timestamp!

        if @publish == true
          @consultant.update!(profile_status: "published", profile_completed_at: Time.current)
        elsif @publish == false
          @consultant.update!(profile_status: "draft")
        end
      end
    end

    def sync_completion_timestamp!
      result = Consultants::ProfileCompleteness.call(@consultant)
      @consultant.update!(
        profile_completed_at: result.complete ? (@consultant.profile_completed_at || Time.current) : nil
      )
    end

    private

    def sync_experiences!
      @consultant.consultant_experiences.destroy_all
      Array(@experiences).each_with_index do |attrs, index|
        @consultant.consultant_experiences.create!(
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
