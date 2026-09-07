# frozen_string_literal: true

module Api
  module V1
    module Public
      class ReportsController < ApplicationController
        def show
          share = ReportShare.find_by(token: params[:token])
          report = share&.report || Report.find_by(share_token: params[:token])
          # A ReportShare row names its rendering. A bare legacy token predates
          # variants and can only ever have meant the full report.
          variant = share&.variant || Reports::VariantSpec::FULL

          return head :not_found unless resolvable?(report, share)

          key, content_type = artifact_for(report, variant)
          return head :not_found if key.blank?

          ReportShareAccess.create!(
            report: report,
            share_token: params[:token],
            variant: variant,
            ip_address: request.remote_ip,
            user_agent: request.user_agent.to_s.truncate(500),
            accessed_at: Time.current
          )

          data = Storage::MinioClient.new.download(key)
          send_data data,
                    filename: "#{filename_for(variant)}-v#{report.version}.#{content_type == 'application/pdf' ? 'pdf' : 'html'}",
                    type: content_type,
                    disposition: "inline"
        end

        private

        def resolvable?(report, share)
          return false if report.blank?
          return false unless report.visibility == "shared_with_company" && report.status == "ready"

          share ? share.active? : report.share_active?
        end

        def artifact_for(report, variant)
          if variant == Reports::VariantSpec::FULL
            [report.storage_key, report.content_type]
          else
            artifact = report.artifact_for(variant)
            [artifact&.storage_key, artifact&.content_type]
          end
        end

        def filename_for(variant)
          variant == Reports::VariantSpec::EXEC_BRIEF ? "executive-brief" : "discovery-report"
        end
      end
    end
  end
end
