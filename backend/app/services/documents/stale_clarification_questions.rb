# frozen_string_literal: true

module Documents
  class StaleClarificationQuestions
    OPEN_STATUSES = %w[open pending_rag].freeze

    def self.for_document!(document:)
      new(company: document.company, document: document).call
    end

    def self.for_company!(company:)
      new(company: company, document: nil).call
    end

    def initialize(company:, document:)
      @company = company
      @document = document
    end

    def call
      scope = @company.company_clarification_questions.where(status: OPEN_STATUSES)
      if @document
        run_ids = DocumentAnalysisRun
          .where(company_id: @company.id)
          .where("document_ids @> ARRAY[?]::bigint[]", @document.id)
          .pluck(:id)
        scope = scope.where(document_analysis_run_id: run_ids) if run_ids.any?
      end
      scope.update_all(status: "stale", updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
