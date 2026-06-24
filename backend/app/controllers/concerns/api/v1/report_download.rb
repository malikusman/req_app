# frozen_string_literal: true

module Api
  module V1
    module ReportDownload
      extend ActiveSupport::Concern

      private

      def send_report_download(report, disposition: "attachment")
        unless report.status == "ready" && report.storage_key.present?
          return render json: { error: "Report not ready" }, status: :not_found
        end

        data = Storage::MinioClient.new.download(report.storage_key)
        ext = report.content_type == "application/pdf" ? "pdf" : "html"
        send_data data,
                  filename: "discovery-report-v#{report.version}.#{ext}",
                  type: report.content_type,
                  disposition: disposition
      end
    end
  end
end
