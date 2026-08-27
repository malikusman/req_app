# frozen_string_literal: true

module Discovery
  # Builds the consultant handover from a finished interview.
  #
  # Runs from a job, never inline: it makes an LLM call, and inlining it would make
  # the employee's final message hang while the package is written.
  #
  # An addendum reopen mints the next version and supersedes the previous one,
  # carrying the consultant's edits forward — without that, a consultant's
  # amendments vanish the moment an employee adds one more thought.
  class BuildPackageService
    def self.call(conversation:)
      new(conversation: conversation).call
    end

    def initialize(conversation:)
      @conversation = conversation
      @employee = conversation.employee
      @company = conversation.company
    end

    def call
      previous = current_package
      package = create_package!(previous)

      payload = fetch_payload
      apply!(package, payload)
      carry_forward_consultant_edits!(previous, package) if previous
      previous&.update!(status: "superseded")

      package
    rescue StandardError => e
      Rails.logger.error("[Discovery::BuildPackage] conversation=#{@conversation.id} #{e.class}: #{e.message}")
      package&.update!(status: "failed", error_message: e.message)
      raise
    end

    private

    def current_package
      DiscoveryPackage.current.where(conversation: @conversation).order(version: :desc).first
    end

    def create_package!(previous)
      DiscoveryPackage.create!(
        conversation: @conversation,
        employee: @employee,
        company: @company,
        version: (previous&.version || 0) + 1,
        status: "generating"
      )
    end

    def fetch_payload
      Langgraph::Client.new.build_discovery_package!(
        blackboard: @conversation.blackboard,
        profile: @conversation.blackboard["profile"] || @employee.profile_card,
        company_name: @company.display_name || @company.name,
        language: @employee.preferred_language.presence || @company.locale || "en",
        insights: recent_insights
      )
    end

    def recent_insights
      @conversation.conversation_insights
                   .order(:turn_number)
                   .limit(20)
                   .filter_map { |i| i.summary.presence }
    end

    def apply!(package, payload)
      package.update!(
        recommendation: payload["recommendation"],
        recommendation_rationale: payload["recommendation_rationale"],
        confidence: payload["confidence"],
        generated_by: payload["generated_by"],
        agent_payload: payload,
        generated_at: Time.current,
        status: "ready"
      )

      issues = create_items!(package, payload["issues"], kind: "issue")
      create_items!(package, payload["solutions"], kind: "solution", issues_by_title: issues)
      create_followups!(package, payload["followup_questions"])
    end

    def create_items!(package, raw, kind:, issues_by_title: nil)
      by_title = {}
      Array(raw).each_with_index do |item, index|
        next unless item.is_a?(Hash)
        next if item["body"].blank?

        record = package.discovery_package_items.create!(
          kind: kind,
          title: item["title"],
          body: item["body"],
          impact: item["impact"],
          origin: "agent",
          status: "proposed",
          ordinal: index,
          # A solution names the issue it answers by title; resolve that to the row.
          linked_item: issues_by_title&.[](item["addresses"].to_s.strip)
        )
        by_title[record.title.to_s.strip] = record if record.title.present?
      end
      by_title
    end

    def create_followups!(package, raw)
      Array(raw).each_with_index do |item, index|
        next unless item.is_a?(Hash)
        next if item["body"].blank?

        package.discovery_followup_questions.create!(
          body: item["body"],
          rationale: item["rationale"],
          status: "drafted",
          # Position 1 is the question that goes out next.
          queue_position: index + 1,
          source_parked_ref: item["from_parked"].present? ? { "note" => item["from_parked"] } : {}
        )
      end
    end

    # Same intent as Reports::GenerateReportService#carry_forward_overrides!: the
    # expert's work must survive a regeneration. Consultant-authored items are
    # copied, and a rejection of an agent item is re-applied by matching body text.
    def carry_forward_consultant_edits!(previous, package)
      previous.discovery_package_items.where(origin: "consultant").find_each do |item|
        package.discovery_package_items.create!(
          kind: item.kind,
          title: item.title,
          body: item.body,
          impact: item.impact,
          evidence_refs: item.evidence_refs,
          origin: "consultant",
          status: item.status,
          ordinal: item.ordinal
        )
      end

      rejected = previous.discovery_package_items.where(origin: "agent", status: "rejected").pluck(:body)
      return if rejected.empty?

      package.discovery_package_items.where(origin: "agent", body: rejected)
             .update_all(status: "rejected", updated_at: Time.current)
    rescue StandardError => e
      # A carry-forward failure must not lose the new package.
      Rails.logger.warn("[Discovery::BuildPackage] carry-forward skipped: #{e.class}: #{e.message}")
    end
  end
end
