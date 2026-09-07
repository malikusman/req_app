# frozen_string_literal: true

module Api
  module V1
    module ReportDownload
      extend ActiveSupport::Concern

      private

      # A report ships as several renderings of one reviewed analysis. The full
      # report also stays on reports.storage_key, so a request with no variant
      # keeps behaving exactly as it did before variants existed.
      def send_report_download(report, disposition: "attachment", variant: nil)
        variant = normalize_variant(variant)
        return if performed?

        if variant == Reports::VariantSpec::FULL
          key = report.storage_key
          content_type = report.content_type
        else
          artifact = report.artifact_for(variant)
          key = artifact&.storage_key
          content_type = artifact&.content_type
        end

        unless report.status == "ready" && key.present?
          return render json: { error: "Report not ready" }, status: :not_found
        end

        data = Storage::MinioClient.new.download(key)
        ext = content_type == "application/pdf" ? "pdf" : "html"
        send_data data,
                  filename: "#{download_basename(variant)}-v#{report.version}.#{ext}",
                  type: content_type,
                  disposition: disposition
      end

      def normalize_variant(raw)
        value = raw.presence || params[:variant].presence || Reports::VariantSpec::FULL
        unless Reports::VariantSpec::VARIANTS.include?(value.to_s)
          render json: { error: "Unknown report variant" }, status: :unprocessable_entity
          return nil
        end
        value.to_s
      end

      def download_basename(variant)
        variant == Reports::VariantSpec::EXEC_BRIEF ? "executive-brief" : "discovery-report"
      end

      # What the portal needs to offer both downloads honestly: which variants
      # exist, and how many pages each is. "4 pp" on the button is the whole
      # reason the brief gets clicked.
      def report_artifacts_json(report)
        Reports::VariantSpec.all.filter_map do |spec|
          if spec[:variant] == Reports::VariantSpec::FULL
            next nil if report.storage_key.blank?

            page_count = report.artifact_for(spec[:variant])&.page_count
            content_type = report.content_type
          else
            artifact = report.artifact_for(spec[:variant])
            next nil if artifact&.storage_key.blank?

            page_count = artifact.page_count
            content_type = artifact.content_type
          end

          {
            variant: spec[:variant],
            label: spec[:label],
            description: spec[:description],
            orientation: spec[:orientation],
            page_count: page_count,
            content_type: content_type,
            is_pdf: content_type == "application/pdf"
          }
        end
      end
    end
  end
end
