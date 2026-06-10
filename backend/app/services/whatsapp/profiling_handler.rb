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

    def initialize(employee:, conversation:, client: MetaClient.new)
      @employee = employee
      @company = employee.company
      @conversation = conversation
      @client = client
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
        complete_profiling!
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

    def complete_profiling!
      snapshot = @conversation.state_snapshot.merge(
        "profiling" => profiling_state.merge("step" => nil, "completed_at" => Time.current.iso8601),
        "blackboard" => @conversation.blackboard.merge("profile" => @employee.profile_card)
      )
      @conversation.update!(status: "discovery", state_snapshot: snapshot)

      route_agents!
      send_text(bridging_message)
      run_first_discovery_turn!
    end

    def route_agents!
      return unless @company.merged_settings["discovery_multi_agent_enabled"]

      result = Langgraph::Client.new.route!(
        thread_id: ensure_thread_id,
        profile: @employee.profile_card,
        limits: Discovery::ContextBuilder.limits_for(@company),
        context: { question_target: @company.merged_settings.fetch("discovery_question_target", 10).to_i }
      )
      @conversation.update_blackboard!(
        "agent_queue" => result["agents"],
        "skipped_agents" => result["skipped"],
        "total_budget" => result["total_budget"]
      )
    rescue Langgraph::UnavailableError => e
      # The agent service builds a default queue from the profile on first turn.
      Rails.logger.warn("[Profiling] agent routing failed, deferring to first turn: #{e.message}")
    end

    def ensure_thread_id
      return @conversation.langgraph_thread_id if @conversation.langgraph_thread_id.present?

      thread_id = Langgraph::Client.new.create_thread!
      @conversation.update!(langgraph_thread_id: thread_id)
      thread_id
    end

    def run_first_discovery_turn!
      kickoff = profile_summary_message

      result = Discovery::ProcessTurnService.call(
        conversation: @conversation,
        employee: @employee,
        user_message: kickoff
      )
      Whatsapp::DiscoveryHandler.new(employee: @employee, conversation: @conversation, client: @client)
                                .deliver_assistant_reply(result)
    end

    def profile_summary_message
      profile = @employee.profile_card
      parts = ["I'm #{profile['name']}, a #{profile['role_title']} in #{profile['department']}."]
      parts << profile["responsibilities"] if profile["responsibilities"].present?
      tools = Array(profile["primary_tools"])
      parts << "I mainly use #{tools.join(', ')}." if tools.any?
      parts.join(" ")
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

    def bridging_message
      {
        "en" => "Perfect, thanks #{@employee.display_name.presence || 'there'}! Give me a moment to prepare questions tailored to your role…",
        "es" => "¡Perfecto, gracias #{@employee.display_name.presence || ''}! Dame un momento para preparar preguntas adaptadas a tu rol…"
      }.fetch(locale, "Perfect, thanks! Give me a moment to prepare questions tailored to your role…")
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
        message_type: "text",
        body: body,
        external_id: external_id,
        is_discovery_question: false
      )
    end
  end
end
