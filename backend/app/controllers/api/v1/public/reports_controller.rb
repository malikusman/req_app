# frozen_string_literal: true

module Api
  module V1
    module Public
      class ReportsController < ApplicationController
        include Api::V1::ReportDownload

        MAX_PER_WINDOW = ENV.fetch("PUBLIC_REPORT_RATE_LIMIT_MAX", "10").to_i
        WINDOW = ENV.fetch("PUBLIC_REPORT_RATE_LIMIT_WINDOW", "60").to_i.seconds

        def show
          if rate_limited?
            return render json: { error: "Too many requests. Please try again later." },
                          status: :too_many_requests
          end

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

          send_report_download(report, disposition: "inline")
        end

        private

        def rate_limited?
          key = "public_report_download:#{params[:token]}:#{request.remote_ip}"
          count = Rails.cache.increment(key, 1, expires_in: WINDOW)
          count.nil? ? false : count > MAX_PER_WINDOW
        end
      end
    end
  end
end
