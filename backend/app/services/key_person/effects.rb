# frozen_string_literal: true

module KeyPerson
  # What one captured answer changes beyond the conversation itself.
  #
  # Company facts (Doc 07 §10, Doc 08 §2): a fact the key user mentions that the
  # profile doesn't have yet is written with provenance DISCOVERED_LATER. A fact
  # that differs from one the key user confirmed or entered is never written —
  # the planner keeps it as a contradiction for one light check and for the
  # consultant (§20). Only the key user's conversation writes facts: they own the
  # profile; what other managers say stays in their capture for the consultant.
  #
  # Review (Doc 08 §21): restructuring, legal or regulatory matters and
  # confidential strategy flag the session for the lead consultant. The
  # conversation carries on; nothing of what was said goes into the flag beyond
  # its type and the turn.
  class Effects
    REVIEW_TYPES = %w[RESTRUCTURING LEGAL_OR_REGULATORY CONFIDENTIAL_STRATEGY].freeze

    def initialize(session, capture, turn)
      @session = session
      @capture = capture
      @turn = turn
      @participant = session.participant
      @company = session.company
    end

    def call
      return unless @capture

      write_discovered_facts!
      flag_for_review!
    end

    private

    def write_discovered_facts!
      return unless @participant.key_user?

      profile = (@company.company_profile || {}).to_h
      updates = @capture["profile_facts_discovered"].each_with_object({}) do |fact, acc|
        next if fact["contradicts_known"]
        next if profile[fact["field"]].present?

        value = fact["value"]
        value = value.split(/\s*[,،]\s*/) if Companies::ProfileUpdater::LIST_KEYS.include?(fact["field"])
        acc[fact["field"]] = value
      end
      return if updates.empty?

      Companies::ProfileUpdater.call(company: @company, profile_params: updates, provenance: "DISCOVERED_LATER",
                                     actor: @participant.company_user, only_changed: true)
    rescue StandardError => e
      Rails.logger.warn("[KeyPerson::Effects] facts not written for session #{@session.id}: #{e.class}: #{e.message}")
    end

    def flag_for_review!
      reasons = @capture["sensitive"].select { |s| REVIEW_TYPES.include?(s["type"]) }
                                     .map { |s| { "type" => s["type"], "turn" => @turn.locator } }
      return if reasons.empty?

      first_flag = !@session.needs_review
      @session.update!(needs_review: true, review_reasons: Array(@session.review_reasons) + reasons)
      notify_consultant if first_flag
    end

    def notify_consultant
      consultant = @session.engagement.lead_consultant
      return unless consultant

      NotificationService.notify(
        type: :key_person_review, company: @company, recipients: consultant,
        title: "A leadership conversation needs your review",
        body: "Something raised in a conversation with #{@company.display_name.presence || @company.name}'s " \
              "leadership may need your attention.",
        action_url: "#{NotificationService.app_host}/consultant/companies/#{@company.id}",
        metadata: { conversation_session_id: @session.id }
      )
    end
  end
end
