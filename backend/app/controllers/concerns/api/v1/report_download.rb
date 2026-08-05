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
        send_data data,
                  filename: report_filename(report),
                  type: report.content_type,
                  disposition: disposition
      end

      def send_report_preview(report)
        return head :unprocessable_entity if report.report_snapshot.blank?

        html = Reports::RegenerateWithReviewService.render_html(report: report)
        send_data html, type: "text/html", disposition: "inline"
      end

      def report_filename(report)
        "discovery-report-v#{report.version}.#{report_file_extension(report)}"
      end

      def report_file_extension(report)
        report.content_type == "application/pdf" ? "pdf" : "html"
      end

      def download_disposition
        params[:inline].present? ? "inline" : "attachment"
      end
    end
  end
end
