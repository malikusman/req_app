# frozen_string_literal: true

module Whatsapp
  # Deterministic profiling state machine that runs between consent and discovery.
  # Collects role_title, department (if missing), seniority, responsibilities,
  # team_size (managers+), and primary_tools — then routes into multi-agent discovery.
  class ProfilingHandler
    STEPS = %w[role_title department seniority responsibilities team_size primary_tools].freeze

    SENIORITY_KEYWORDS = {
      "individual_contributor" => /individual|contributor|\bic\b|specialist|analyst|associate|staff/i,
      "team_lead" => /team\s*lead|\blead\b|senior/i,
      "manager" => /manager|head of|supervisor/i,
      "director" => /director|\bvp\b|vice president/i,
      "executive" => /executive|chief|c-?level|ceo|cfo|coo|cto|founder|owner/i
    }.freeze

    def self.enabled?(company)
      company.merged_settings["discovery_profiling_enabled"] == true
    end

    def initialize(employee:, conversation:, client: MetaClient.new, channel: "whatsapp")
      @employee = employee
      @company = employee.company
      @conversation = conversation
      @client = client
      @channel = channel
    end

    # Sends the profiling intro + first question. Called once after consent.
    def start!
      @conversation.update!(status: "profiling") unless @conversation.profiling?
      pending = next_pending_step
      return complete_profiling! unless pending

      set_step(pending)
      send_text(intro_message)
      ask_current_step
    end

    def handle_inbound_text(text, external_id: nil)
      text = text.to_s.strip
      return handle_opt_out if opt_out?(text)

      @conversation.touch_activity!
      @employee.update!(last_active_at: Time.current)
      persist_message(direction: "inbound", body: text, external_id: external_id)

      capture_answer(current_step, text)

      pending = next_pending_step
      if pending
        set_step(pending)
        ask_current_step
      else
        complete_profiling!(trigger_message_id: external_id)
      end
    end

    private

    def current_step
      profiling_state["step"]
    end

    def profiling_state
      @conversation.state_snapshot["profiling"] || {}
    end

    def set_step(step)
      snapshot = @conversation.state_snapshot.merge(
        "profiling" => profiling_state.merge("step" => step)
      )
      @conversation.update!(state_snapshot: snapshot)
    end

    def next_pending_step
      STEPS.find { |step| step_pending?(step) }
    end

    def step_pending?(step)
      case step
      when "role_title" then @employee.role_title.blank?
      when "department" then @employee.department.blank?
      when "seniority" then @employee.seniority.blank?
      when "responsibilities" then @employee.profile_data["responsibilities"].blank?
      when "team_size" then @employee.manager_or_above? && @employee.profile_data["team_size"].blank?
      when "primary_tools" then @employee.profile_data["primary_tools"].blank?
      else false
      end
    end

    def capture_answer(step, text)
      case step
      when "role_title"
        @employee.update!(role_title: text.truncate(120))
      when "department"
        @employee.update!(department: normalize_department(text))
      when "seniority"
        @employee.update!(seniority: parse_seniority(text))
      when "responsibilities"
        merge_profile!("responsibilities" => text.truncate(500))
      when "team_size"
        merge_profile!("team_size" => text[/\d+/]&.to_i)
      when "primary_tools"
        merge_profile!("primary_tools" => parse_tools(text))
      end
    end

    def merge_profile!(updates)
      profile = @employee.profile_data.merge(updates)
      @employee.update!(metadata: @employee.metadata.merge("profile" => profile))
    end

    def normalize_department(text)
      cleaned = text.downcase.strip
      known = DiscoveryPlaybook.distinct.pluck(:department) - ["default"]
      known.find { |dept| cleaned.include?(dept) } || cleaned.truncate(60)
    end

    def parse_seniority(text)
      SENIORITY_KEYWORDS.reverse_each do |level, pattern|
        return level if text.match?(pattern)
      end
      "individual_contributor"
    end

    def parse_tools(text)
      text.split(/[,;\n]|\band\b/i).map(&:strip).reject(&:blank?).first(8)
    end

    def complete_profiling!(trigger_message_id: nil)
      snapshot = @conversation.state_snapshot.merge(
        "profiling" => profiling_state.merge("step" => nil, "completed_at" => Time.current.iso8601),
        "blackboard" => @conversation.blackboard.merge("profile" => @employee.profile_card)
      )
      @conversation.update!(status: "discovery", state_snapshot: snapshot)

      Discovery::ProactiveStartService.call(
        conversation: @conversation,
        employee: @employee,
        client: @client,
        trigger_message_id: trigger_message_id,
        delivery_channel: @channel == "web" ? :web : :whatsapp
      )
    end

    def ask_current_step
      send_text(question_for(current_step))
    end

    def question_for(step)
      lang = locale
      questions = {
        "role_title" => {
          "en" => "What's your job title or role?",
          "es" => "¿Cuál es tu puesto o rol?"
        },
        "department" => {
          "en" => "Which team or department are you part of?",
          "es" => "¿De qué equipo o departamento formas parte?"
        },
        "seniority" => {
          "en" => "Would you say you're an individual contributor, a team lead, a manager, or an executive?",
          "es" => "¿Dirías que eres contribuidor individual, líder de equipo, gerente o ejecutivo?"
        },
        "responsibilities" => {
          "en" => "In one or two sentences, what do you spend most of your time on at work?",
          "es" => "En una o dos frases, ¿en qué pasas la mayor parte de tu tiempo en el trabajo?"
        },
        "team_size" => {
          "en" => "Roughly how many people are on your team?",
          "es" => "¿Aproximadamente cuántas personas hay en tu equipo?"
        },
        "primary_tools" => {
          "en" => "Which tools or systems do you use every day? (e.g. SAP, Excel, Salesforce)",
          "es" => "¿Qué herramientas o sistemas usas todos los días? (p. ej. SAP, Excel, Salesforce)"
        }
      }
      questions.fetch(step).fetch(lang, questions.fetch(step)["en"])
    end

    def intro_message
      {
        "en" => "Thank you! Before we dive in, I'd like to learn a little about your role so I can ask the right questions.",
        "es" => "¡Gracias! Antes de empezar, me gustaría conocer un poco tu rol para hacerte las preguntas adecuadas."
      }.fetch(locale, "Thank you! Before we dive in, I'd like to learn a little about your role so I can ask the right questions.")
    end

    def handle_opt_out
      @employee.update!(participation_status: "declined")
      @conversation.update!(status: "abandoned", abandoned_at: Time.current, abandon_reason: "opt_out")
      send_text("You've been unsubscribed. Reply anytime if your admin sends a new invitation.")
    end

    def opt_out?(text)
      %w[stop unsubscribe cancel].include?(text.downcase)
    end

    def locale
      @employee.preferred_language.presence || @company.locale
    end

    def send_text(body)
      persist_message(direction: "outbound", body: body)
      if @client.configured?
        @client.send_text(to: @employee.phone_e164, body: body)
      else
        Rails.logger.info("[WhatsApp dev] to=#{@employee.phone_e164} body=#{body}")
      end
    end

    def persist_message(direction:, body:, external_id: nil)
      Message.create!(
        conversation: @conversation,
        direction: direction,
        channel: @channel,
        message_type: "text",
        body: body,
        external_id: external_id,
        is_discovery_question: false
      )
    end
  end
end
