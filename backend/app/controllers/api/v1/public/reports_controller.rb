# frozen_string_literal: true

module Api
  module V1
    module Public
      class ReportsController < ApplicationController
        def show
          report = Report.find_by(share_token: params[:token])
          unless report&.share_active? && report.visibility == "shared_with_company" && report.status == "ready"
            return head :not_found
          end

          ReportShareAccess.create!(
            report: report,
            share_token: params[:token],
            ip_address: request.remote_ip,
            user_agent: request.user_agent.to_s.truncate(500),
            accessed_at: Time.current
          )

          data = Storage::MinioClient.new.download(report.storage_key)
          send_data data,
                    filename: "discovery-report-v#{report.version}.pdf",
                    type: report.content_type,
                    disposition: "inline"
        end
      end
    end
  end
end
