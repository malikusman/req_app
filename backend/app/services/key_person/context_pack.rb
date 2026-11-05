# frozen_string_literal: true

module KeyPerson
  # What a prompt in the conversation with leadership may see (Doc 08 §5, §27;
  # Doc 05 §4.3). Built for one session only:
  #
  #   - the company's confirmed facts and systems (never unconfirmed website
  #     proposals, which stay on the pre-fill records);
  #   - this person: name, role, persona, scope, language;
  #   - this session's own turns and running summary;
  #   - the consultant's neutral focus, if any, fenced as consultant guidance.
  #
  # Never: anything from employee interviews, another key person's
  # conversation, commercial data, or consultant notes beyond that focus line.
  # The classes used are logged with each run (Doc 05 §4.6).
  class ContextPack
    CONTEXT_CLASSES = %w[PUBLIC_COMPANY_CONTEXT MANAGEMENT_STRATEGIC_OWN].freeze
    RECENT_TURNS = 8
    LANGUAGE_NAMES = { "en" => "English", "ar" => "Modern Standard Arabic" }.freeze

    attr_reader :session

    def initialize(session)
      @session = session
      @participant = session.participant
      @company = session.company
    end

    def language = session.language.to_s.start_with?("ar") ? "ar" : "en"

    # How P02 is told which language to reply in (P02 §10.7, Reg F4).
    def language_instruction
      return "English" unless language == "ar"

      "Modern Standard Arabic (switch to the participant's own dialect only if they write in it)"
    end

    def persona = @participant.persona.presence || "OTHER"

    def scope
      @participant.scope.presence || @participant.department.presence ||
        (Personas.company_wide?(persona) ? "Company-wide" : "Not stated")
    end

    def participant_block
      fenced("participant", "platform", <<~TEXT)
        name: #{clean(@participant.name)}
        role: #{clean(@participant.role_title.presence || 'Not stated')}
        persona: #{persona}
        scope: #{clean(scope)}
        language: #{LANGUAGE_NAMES.fetch(language)}
      TEXT
    end

    # The confirmed profile (onboarding facts and what was learned later) and the
    # systems the company named. Unknowns are left out rather than shown as gaps.
    def known_facts
      @known_facts ||= begin
        facts = Companies::AgentContext.profile_slice(@company).reject { |_, v| v.blank? }
        facts = { "company_name" => @company.display_name.presence || @company.name }.merge(facts)
        systems = Companies::AgentContext.known_systems(@company).map { |s| s["name"] }
        systems.any? ? facts.merge("known_systems" => systems) : facts
      end
    end

    def known_fields = known_facts.keys - ["company_name"]

    def known_facts_block
      lines = known_facts.map { |key, value| "#{key}: #{Array(value).join(', ')}" }
      fenced("company_known_facts", "platform", lines.join("\n"))
    end

    def consultant_focus_block
      focus = @participant.consultant_focus.to_s.squish.presence || "none"
      fenced("consultant_focus", "consultant", focus)
    end

    def summary_block(summary)
      lines = Array(summary).map { |s| "#{s['area']}: #{s['text']}" }
      fenced("conversation_summary", "platform", lines.presence&.join("\n") || "Nothing yet.")
    end

    def recent_questions_block(questions)
      fenced("recent_questions", "platform", Array(questions).join("\n").presence || "None yet.")
    end

    # The last several turns, always including the opening, so the assistant
    # doesn't repeat itself (P02 §4).
    def recent_turns_block
      history = session.history.to_a
      shown = (history.first(1) + history.last(RECENT_TURNS)).uniq
      lines = shown.map { |t| "#{t.assistant? ? 'ASSISTANT' : 'PARTICIPANT'} (#{t.locator}): #{clean(t.text)}" }
      "<recent_turns>\n#{lines.join("\n")}\n</recent_turns>"
    end

    # The participant's own recent words: what licenses the assistant to echo a
    # word it would otherwise never bring up (Guard).
    def recent_participant_text
      session.history.from_participant.last(3).map(&:text).join("\n")
    end

    def coverage_block(coverage)
      lines = Coverage::AREAS.map { |area| "#{area}: #{coverage.dig(area, 'status') || 'OPEN'}" }
      fenced("coverage_state", "platform", lines.join("\n"))
    end

    def answer_block(turn)
      "<participant_answer trust=\"participant\" turn_id=\"#{turn.locator}\">\n#{clean(turn.text)}\n</participant_answer>"
    end

    def context_classes
      @participant.consultant_focus.present? ? CONTEXT_CLASSES + ["CONSULTANT_FOCUS"] : CONTEXT_CLASSES
    end

    # A participant's words can't close the block they sit in, or open a new one
    # that looks like platform instructions (Doc 05 §14).
    def clean(text)
      text.to_s.gsub(%r{</?\s*[a-z_][\w-]*[^>]*>}i) { |tag| tag.tr("<>", "‹›") }
    end

    private

    def fenced(name, trust, body)
      "<#{name} trust=\"#{trust}\">\n#{body.to_s.strip}\n</#{name}>"
    end
  end
end
