# frozen_string_literal: true

module Discovery
  # Document 02: deny by default. No peer memory, management context, consultant
  # notes or general knowledge retrieval enters the employee interview.
  class EmployeeContext
    BASICS = %w[industry sub_industry size_band region country org_departments known_systems].freeze
    SEED = %w[role_title department responsibilities primary_tools].freeze
    SECRET = /sk-[A-Za-z0-9_-]{16,}|(?:password|api[_ -]?key|access[_ -]?token|secret)\s*[:=]\s*\S+/i
    NUMBER_WORDS = %w[zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty].zip((0..20).to_a).to_h.merge(
      'thirty' => 30, 'forty' => 40, 'fifty' => 50, 'sixty' => 60, 'ninety' => 90, 'half' => 0.5, 'quarter' => 0.25, 'couple' => 2,
      'واحد' => 1, 'واحدة' => 1, 'اثنين' => 2, 'اثنتين' => 2, 'ثلاث' => 3, 'ثلاثة' => 3, 'أربع' => 4, 'أربعة' => 4,
      'خمس' => 5, 'خمسة' => 5, 'عشر' => 10, 'عشرة' => 10, 'عشرين' => 20, 'ثلاثين' => 30, 'نصف' => 0.5, 'نص' => 0.5, 'ربع' => 0.25).freeze

    def self.evidence_numbers(text)
      normalized = text.to_s.tr('٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹', '01234567890123456789')
      numbers = normalized.scan(/\d+(?:[.,]\d+)?|\.\d+/).map { |n| n.tr(',', '.').to_f }
      words = normalized.downcase.scan(/[[:word:]]+/)
      numbers.concat(words.filter_map { |w| NUMBER_WORDS[w] })
      words.each_cons(2) do |a, b|
        numbers << NUMBER_WORDS[a] + NUMBER_WORDS[b] if NUMBER_WORDS[a].to_i >= 20 && (1..9).cover?(NUMBER_WORDS[b].to_i)
      end
      numbers << 1 if normalized.match?(/\ban? (?:hour|day)\b/i)
      # "an hour and a half", "two days and a half" are said as one estimate.
      normalized.scan(/(\d+(?:\.\d+)?|\ban?\b|[a-z]+)\s+(?:hours?|days?)\s+and\s+a\s+half\b/i).flatten.each do |whole|
        base = whole =~ /\A(?:an?)\z/i ? 1 : whole =~ /\A\d/ ? whole.to_f : NUMBER_WORDS[whole.downcase]
        numbers << base + 0.5 if base
      end
      numbers.uniq
    end

    def self.v2?(conversation)
      bb = conversation.blackboard
      return true if bb['employee_discovery_v2'].is_a?(Hash) || conversation.state_snapshot['discovery_engine_version'] == 2
      return false if conversation.state_snapshot['discovery_engine_version'] == 1
      conversation.company.merged_settings['discovery_multi_agent_enabled'] == true &&
        bb.except('profile').blank? && conversation.question_count.zero?
    end

    def self.redact(value)
      case value
      when String then value.gsub(SECRET, '[REDACTED]')
      when Array then value.map { |item| redact(item) }
      when Hash then value.transform_values { |item| redact(item) }
      else value
      end
    end

    def self.basics(company)
      redact(Companies::AgentContext.for_agents(company).slice(*BASICS))
    end

    def self.policy(conversation)
      { stage_id: 'EMPLOYEE_DISCOVERY', actor_role: 'AI_SERVICE', purpose: 'broad_role_inventory',
        allowed_context_classes: %w[PUBLIC_COMPANY_CONTEXT EMPLOYEE_DISCOVERY],
        blocked_context_classes: %w[MANAGEMENT_STRATEGIC OTHER_EMPLOYEE_PRIVATE CONSULTANT_PRIVATE TECHNICAL_SENSITIVE RESTRICTED],
        object_filters: { company_id: conversation.company_id, participant_id: conversation.employee_id, conversation_id: conversation.id },
        sensitivity_ceiling: 'CONFIDENTIAL', evidence_retrieval_policy: 'OWN_CONVERSATION_ONLY',
        tool_permissions: [], policy_version: 'employee-discovery-context-v2.1' }
    end
  end
end
