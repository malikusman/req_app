# frozen_string_literal: true

module Api
  module V1
    module Company
      class ReportsController < BaseController
        include Api::V1::ReportDownload

        def index
          reports = policy_scope(Report).where(visibility: "shared_with_company").order(version: :desc)
          latest_ready = reports.find { |r| r.status == "ready" }
          intel_at = current_company.intelligence_updated_at
          stale = intel_at.present? && latest_ready&.generated_at.present? && intel_at > latest_ready.generated_at

          render json: {
            reports: reports.map { |r| report_json(r) },
            intelligence_updated_at: intel_at,
            report_stale: stale,
            latest_ready_generated_at: latest_ready&.generated_at
          }
        end

        def show
          report = policy_scope(Report).find(params[:id])
          authorize report, :show?
          return render json: { error: "Report not available" }, status: :forbidden if report.visibility != "shared_with_company"

          payload = { report: report_json(report, detailed: true) }
          if report.status == "ready"
            payload[:expert_consultants] = expert_consultants_for_company
          end
          render json: payload
        end

        def download
          report = policy_scope(Report).find(params[:id])
          authorize report, :download?
          return render json: { error: "Report not ready" }, status: :not_found unless report.status == "ready"
          return render json: { error: "Report not available" }, status: :forbidden if report.visibility != "shared_with_company"

          send_report_download(report, disposition: params[:inline].present? ? "inline" : "attachment")
        end

        # The in-portal reader renders the report's own HTML so it can offer real
        # section jump links, which a scaled page image cannot. It serves the
        # STORED html behind the approved PDF, not a live re-render: a live one
        # would drift the moment a consultant touched an override after
        # approval, and could show the client an un-approved edit.
        def read
          report = policy_scope(Report).find(params[:id])
          authorize report, :download?
          return render json: { error: "Report not ready" }, status: :not_found unless report.status == "ready"
          return render json: { error: "Report not available" }, status: :forbidden if report.visibility != "shared_with_company"

          variant = normalize_variant(nil)
          return if performed?

          key = reader_key_for(report, variant)
          return render json: { error: "This report has no readable version — download the PDF instead." }, status: :not_found if key.blank?

          html = Storage::MinioClient.new.download(key)
          # Rendered in a sandboxed iframe by the portal. Served as a document
          # rather than JSON so the report's own stylesheet applies unchanged.
          render html: html.to_s.html_safe, layout: false
        end

        def share
          report = policy_scope(Report).find(params[:id])
          authorize report, :share?
          variant = normalize_variant(nil)
          return if performed?

          days = params[:days].to_i
          result = Reports::ShareLinkService.create!(
            report: report, days: days.positive? ? days : 30, variant: variant
          )
          render json: result
        rescue ArgumentError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        def revoke_share
          report = policy_scope(Report).find(params[:id])
          authorize report, :share?
          # No variant revokes every link for this report.
          Reports::ShareLinkService.revoke!(report: report, variant: params[:variant].presence)
          render json: report_json(report.reload, detailed: true)
        end

        private

        # Older reports predate stored reader HTML; the full variant can still
        # fall back to reports.storage_key when Gotenberg was down and the
        # artifact IS the HTML.
        def reader_key_for(report, variant)
          artifact = report.artifact_for(variant)
          return artifact.reader_storage_key if artifact&.reader_storage_key.present?
          return artifact.storage_key if artifact&.content_type == "text/html"
          return report.storage_key if variant == Reports::VariantSpec::FULL && report.content_type == "text/html"

          nil
        end

        def expert_consultants_for_company
          current_company.consultant_assignments.active
            .includes(:consultant_user)
            .map(&:consultant_user)
            .select(&:published_profile?)
            .map { |r| Consultants::ProfileSerializer.public_card(r, request: request) }
        end

        # One row per live link so the UI can label what each one opens, rather
        # than showing a single anonymous "Shared" pill.
        def report_shares_json(report)
          report.report_shares.live.order(:created_at).map do |share|
            spec = Reports::VariantSpec.for(share.variant)
            {
              id: share.id,
              variant: share.variant,
              variant_label: spec[:label],
              expires_at: share.expires_at,
              share_url: "#{ENV.fetch('API_PUBLIC_HOST', 'http://localhost:3000')}/api/v1/public/reports/#{share.token}",
              access_count: report.report_share_accesses.where(share_token: share.token).count
            }
          end
        end

        def report_json(report, detailed: false)
          access_count = report.report_share_accesses.count
          last_access = report.report_share_accesses.maximum(:accessed_at)

          json = {
            id: report.id,
            version: report.version,
            status: report.status,
            visibility: report.visibility,
            review_workflow_status: report.review_workflow_status,
            generated_at: report.generated_at,
            share_token_expires_at: report.share_token_expires_at,
            share_active: report.share_active?,
            access_count: access_count,
            last_accessed_at: last_access,
            delta_summary: report.report_snapshot.dig("delta_from_previous", "summary"),
            error_message: report.error_message,
            artifacts: report_artifacts_json(report),
            shares: report_shares_json(report)
          }

          if detailed
            # The stored snapshot is the untouched machine analysis; the expert
            # layer (the consultant's verdict, the opportunity figure they sized,
            # who validated it) is applied at RENDER time, so it is in the PDF
            # and was missing from every API response. The portal hero reads
            # exactly these fields, so without this it could never show the one
            # number an owner most wants.
            #
            # Merged into the response, never into the stored column.
            expert = Reports::ExpertLayer.call(report: report)
            json[:report_snapshot] = expert.present? ? report.report_snapshot.merge("expert" => expert) : report.report_snapshot
          end
          json[:share_url] = "#{ENV.fetch('API_PUBLIC_HOST', 'http://localhost:3000')}/api/v1/public/reports/#{report.share_token}" if report.share_token.present?
          json
        end
      end
    end
  end
end
