# frozen_string_literal: true

module Documents
  class StartAnalysisRunService
    class Error < StandardError; end

    def self.call(company:, user:, run_kind: "full", document_ids: nil)
      new(company: company, user: user, run_kind: run_kind, document_ids: document_ids).call
    end

    def initialize(company:, user:, run_kind:, document_ids:)
      @company = company
      @user = user
      @run_kind = run_kind.to_s
      @document_ids = Array(document_ids).map(&:to_i).reject(&:zero?)
    end

    def call
      raise Error, "Invalid run kind" unless DocumentAnalysisRun::RUN_KINDS.include?(@run_kind)

      run = nil
      @company.with_lock do
        raise Error, "Analysis already in progress" if @company.document_analysis_runs.active.exists?

        if @run_kind == "profile_reground"
          raise Error, "No analyzed documents yet" unless @company.documents.ready.exists?
        elsif @run_kind == "incremental_docs"
          pending = @company.documents.portal.awaiting_analysis.to_a
          if @document_ids.any?
            pending = (pending + @company.documents.where(id: @document_ids).to_a).uniq(&:id)
          end
          raise Error, "No documents awaiting analysis" if pending.empty?
        else
          raise Error, "Upload at least one document before analyzing" if @company.documents.portal.none?
        end

        run = @company.document_analysis_runs.create!(
          triggered_by_company_user: @user,
          run_kind: @run_kind,
          status: "queued",
          phase: "queued",
          document_ids: @document_ids,
          profile_snapshot: Companies::AgentContext.docs_profile_snapshot(@company),
          model_tier: ENV["DOCS_MODEL_REASONING"].present? ? "reasoning" : "fast"
        )
      end

      DocumentAnalysisRunJob.perform_later(run.id)
      run
    rescue ActiveRecord::RecordNotUnique
      raise Error, "Analysis already in progress"
    end
  end
end
