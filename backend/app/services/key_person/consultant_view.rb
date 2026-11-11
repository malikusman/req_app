# frozen_string_literal: true

module KeyPerson
  # The conversations with leadership as a consultant sees them (Doc 08 §32
  # "consultant utility", Doc 22 E4 "coverage visible to consultant"): everyone
  # taking part, how far each has got, coverage by area, what each conversation
  # produced — findings, planned changes, unknowns, contradictions — the
  # consultant-only political context and notes, review flags, documents, and the
  # transcript with what was captured from each answer.
  #
  # Consultants only. Nothing here is serialised for the client or employees.
  class ConsultantView
    def initialize(engagement)
      @engagement = engagement
    end

    def json
      {
        engagement: {
          id: @engagement.id, status: @engagement.status, planned_departments: @engagement.planned_departments,
          planned_participant_count: @engagement.planned_participant_count,
          plan_editable: @engagement.plan_open_to_mjadi?
        },
        available: Conversation.available?(@engagement.company),
        personas: EngagementParticipant::PERSONAS,
        areas: Coverage::AREAS,
        participants: @engagement.participants.key_persons.order(Arel.sql("source = 'KEY_USER' DESC"), :created_at)
                                 .map { |p| participant_json(p) }
      }
    end

    private

    def participant_json(participant)
      sessions = participant.conversation_sessions.to_a
      {
        id: participant.id, name: participant.name, role_title: participant.role_title, email: participant.email,
        key_user: participant.key_user?, source: participant.source, persona: participant.persona,
        scope: participant.scope, participation_status: participant.participation_status,
        invited_at: participant.invited_at, can_invite: participant.key_user? || participant.email.present?,
        reminder_count: participant.reminder_count, consultant_focus: participant.consultant_focus,
        sessions: sessions.map { |s| session_json(s) },
        contexts: ManagementDiscoveryContext.where(engagement_participant_id: participant.id).order(:version)
                                            .map { |c| context_json(c) }
      }
    end

    def session_json(session)
      snapshot = session.state_snapshot || {}
      {
        id: session.id, version: session.version, state: session.state, close_reason: session.close_reason,
        language: session.language, needs_review: session.needs_review, review_reasons: session.review_reasons,
        turn_count: session.turn_count, started_at: session.started_at, completed_at: session.completed_at,
        last_activity_at: session.last_activity_at,
        coverage: Coverage::AREAS.index_with { |a| snapshot.dig("coverage", a, "status") || "OPEN" },
        contradictions: Array(snapshot["contradictions"]),
        people_mentioned: Array(snapshot["participants_mentioned"]),
        document_requests: DocumentRequest.where(conversation_session_id: session.id).order(:id).map do |r|
          { id: r.id, requested_item: r.requested_item, status: r.status }
        end,
        documents: session.company.documents.leadership
                          .where("metadata->>'conversation_session_id' = ?", session.id.to_s).order(:id)
                          .map { |d| { id: d.id, filename: d.filename, document_request_id: d.document_request_id } },
        transcript: session.turns.map do |t|
          { index: t.turn_index, locator: t.locator, direction: t.direction, text: t.text, mode: t.mode,
            targeted_slot: t.targeted_slot, slots_filled: t.slots_filled, input_mode: t.input_mode,
            fallback_reason: t.fallback_reason, capture: t.capture, at: t.created_at }
        end
      }
    end

    def context_json(context)
      {
        id: context.id, version: context.version, status: context.status, persona: context.persona,
        scope: context.scope, fallback_reason: context.fallback_reason, content: context.content,
        unknowns: context.unknowns, contradictions: context.contradictions, completion: context.completion,
        neutral_employee_context: context.neutral_employee_context, consultant_private: context.consultant_private,
        findings: context.strategic_findings.where.not(status: "SUPERSEDED").order(:id).map do |f|
          f.slice(:id, :version, :status, :category, :scope, :statement, :business_consequence, :symptom_or_cause,
                  :source_basis, :fact_status, :management_importance, :related_departments, :related_systems,
                  :planned_initiative_link, :validation_need, :evidence, :edit_rationale)
        end,
        initiatives: context.planned_initiatives.order(:id).map do |i|
          i.slice(:id, :initiative_type, :description, :timing, :status, :affected_areas, :evidence)
        end
      }
    end
  end
end
