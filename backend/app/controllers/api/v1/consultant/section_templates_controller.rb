# frozen_string_literal: true

module Api
  module V1
    module Consultant
      # The section library a consultant adds report sections from.
      #
      # "Add a section" already worked — ReportSectionOverride action "add", with
      # 14 anchor points. What it lacked was any structure: the consultant got an
      # empty textarea. These are the sections a real strategy deliverable carries
      # and that an evidence-driven generator structurally cannot produce, because
      # they need judgement rather than data — assumptions, risks, quick wins,
      # benchmarks, the options that were rejected.
      class SectionTemplatesController < BaseController
        def index
          render json: {
            templates: ReportSectionTemplates::DEFINITIONS.map { |t| serialize(t) },
            # Where a section may be anchored, so the client can offer a picker
            # rather than expecting the consultant to know section keys.
            anchors: ReportSectionOverride::BUILT_IN_SECTIONS.map do |key|
              { key: key, label: ReportsHelper.section_label(key) }
            end
          }
        end

        private

        def serialize(template)
          {
            key: template["key"],
            title: template["title"],
            purpose: template["purpose"],
            anchor: template["anchor"],
            recommended: template["recommended"] == true,
            scaffold: template["scaffold"]
          }
        end
      end
    end
  end
end
