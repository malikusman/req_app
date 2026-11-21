# frozen_string_literal: true
require 'digest'

module Discovery
  # Canonical Document 03 objects are stored in the existing versioned turn result
  # and conversation snapshot. Tenant IDs and provenance are assigned by Rails,
  # never accepted from a model. The outer durable-turn transaction owns commit.
  class V2Contract
    STATUSES = %w[REPORTED UNKNOWN CONTRADICTED].freeze
    PROBES = %w[SLOWER_THAN_EXPECTED DUPLICATE_ENTRY CHASING_WAITING TRUST_CHECKING OUTSIDE_SYSTEMS].freeze

    def self.prepare!(result, conversation:, source:)
      new(result, conversation, source).prepare!
    end

    def initialize(result, conversation, source)
      @result, @conversation, @source = result, conversation, source
      @data = result.dig('blackboard', 'employee_discovery_v2')
      @refs = {}
    end

    def invalid!(reason)
      raise Langgraph::UnavailableError.new(reason, retryable: false, code: 'invalid_discovery_v2_contract')
    end

    def prepare!
      invalid!('Missing V2 state') unless @data.is_a?(Hash) && @data['version'] == 2
      previous = @conversation.blackboard['employee_discovery_v2'] || {}
      @previous = previous
      invalid!('Invalid V2 revision') unless @data['revision'].is_a?(Integer) && @data['revision'] >= previous.fetch('revision', 0)
      items = @data['work_items']
      invalid!('Invalid work items') unless items.is_a?(Array) && items.all? { |w| w.is_a?(Hash) && w['id'].is_a?(String) && w['id'].match?(/\Awork-\d+\z/) } && items.map { |w| w['id'] }.uniq.size == items.size
      retired = Array(@data['retired_work_items'])
      invalid!('Unsupported inventory withdrawal') unless retired.all? { |w| w.is_a?(Hash) && w.dig('retirement', 'fact_status') == 'REPORTED' && w.dig('retirement', 'evidence').present? }
      invalid!('Work inventory was lost') unless (Array(previous['work_items']).map { |w| w['id'] } - items.map { |w| w['id'] } - retired.map { |w| w['id'] }).empty?
      walk_facts!(@data.slice('work_items', 'retired_work_items', 'checks', 'invisible_work_signals', 'shadow_ai_signals', 'confirmation'))
      validate_effort_inclusions!
      material = @data.slice('work_items', 'retired_work_items', 'checks', 'invisible_work_signals', 'shadow_ai_signals')
      invalid!('Restricted content in capture') unless EmployeeContext.redact(material) == material
      invalid!('Invalid coverage') unless @data['checks'].is_a?(Hash) && (@data['checks'].keys - (%w[anchor weekly monthly seasonal shadow_ai] + PROBES)).empty?
      invalid!('Unsubstantiated coverage') unless @data['checks'].values.all? { |fact| fact.is_a?(Hash) && fact['fact_status'] == 'REPORTED' && fact['value'].is_a?(String) && fact['value'].present? && fact['evidence'].is_a?(Array) && fact['evidence'].present? }
      @data['coverage'] = {
        'regular_work' => items.present? && @data['checks'].key?('anchor'),
        'periodic_work' => %w[weekly monthly seasonal].all? { |k| @data['checks'].key?(k) },
        'invisible_work' => PROBES.all? { |k| @data['checks'].key?(k) },
        'shadow_ai' => @data['checks'].key?('shadow_ai'),
        'sizing' => items.present? && items.all? { |w| sized?(w) }
      }
      validate_completion!(previous)
      role_id = "role-profile-#{@conversation.id}"
      @data['canonical_work_items'] = items.map do |item|
        description = item['description']
        invalid!('Work item requires supported description') unless description.is_a?(Hash) && STATUSES.include?(description['fact_status']) && description['evidence'].present? && description['value'].is_a?(String) && description['value'].present?
        effort = item['effort'] || {}
        inclusion = item['effort_inclusion'] || {}
        included = inclusion['fact_status'] == 'REPORTED'
        separate = inclusion.empty? && effort['fact_status'] == 'REPORTED'
        invalid!('Invalid periodic flag') unless [nil, true, false].include?(item['is_periodic'])
        { **meta(item['id']), 'role_profile_id' => "#{@conversation.id}:#{role_id}", 'description' => description['value'],
          'frequency' => item.dig('frequency', 'fact_status') == 'REPORTED' ? item.dig('frequency', 'value') : nil,
          'effort_range_min' => separate ? effort['minimum'] : nil,
          'effort_range_max' => separate ? effort['maximum'] : nil,
          'effort_unit' => inclusion.present? ? nil : effort['unit'], 'effort_basis' => inclusion.present? ? nil : effort['basis'],
          'effort_included_in_work_item_id' => included ? "#{@conversation.id}:#{inclusion['value']}" : nil,
          'effort_counting' => included ? 'INCLUDED_IN_OTHER_WORK' : inclusion.present? ? 'UNRESOLVED_INCLUSION' : separate && effort['minimum'] ? 'SEPARATE_ESTIMATE' : 'UNKNOWN',
          'systems_touched' => values(item['systems_touched']), 'outputs' => values(item['outputs']),
          'handoffs' => values(item['handoffs']), 'is_periodic' => item['is_periodic'],
          'fact_status' => status_for(item), 'field_statuses' => item.slice('description', 'frequency', 'effort', 'effort_inclusion').transform_values { |v| v['fact_status'] }.merge('is_periodic' => item['is_periodic'].nil? ? 'UNKNOWN' : 'REPORTED'),
          'benefit_state' => 'DISCOVERY_ESTIMATE', 'cluster_id' => nil, 'evidence_refs' => refs_for(item) }
      end
      @data['canonical_retired_work_items'] = retired.filter_map do |item|
        old = (Array(previous['canonical_work_items']) + Array(previous['canonical_retired_work_items'])).find { |w| w['id'] == "#{@conversation.id}:#{item['id']}" }
        next unless old
        old.merge(meta(item['id'])).merge('retired' => true, 'retirement_evidence_refs' => refs_for(item['retirement']))
      end
      @data['role_profile'] = { **meta(role_id), 'participant_id' => @conversation.employee_id,
        'role_title' => @conversation.employee.role_title, 'department' => @conversation.employee.department,
        'reports_to' => nil, 'role_summary' => items.map { |w| w.dig('description', 'value') }.join('; '),
        'fact_status' => items.present? ? 'REPORTED' : 'UNKNOWN',
        'field_statuses' => { 'role_title' => 'UNKNOWN', 'reports_to' => 'UNKNOWN', 'role_summary' => items.present? ? 'REPORTED' : 'UNKNOWN' },
        'systems_used' => @data['canonical_work_items'].flat_map { |w| w['systems_touched'] }.uniq,
        'periodic_work' => items.select { |w| w['is_periodic'] }.map { |w| "#{@conversation.id}:#{w['id']}" },
        'interview_completed_at' => @result['completed'] && @data['outcome'] == 'successful' ? Time.current.iso8601 : nil,
        'modality' => @conversation.messages.where(direction: 'inbound', message_type: 'audio').exists? ? 'VOICE' : 'TEXT',
        'context_class' => 'EMPLOYEE_DISCOVERY', 'evidence_refs' => refs_for(items) }
      @data['canonical_invisible_work_signals'] = Array(@data['invisible_work_signals']).each_with_index.filter_map do |signal, i|
        invalid!('Invalid invisible work link') unless (items + retired).any? { |w| w['id'] == signal['work_item_id'] } && PROBES.include?(signal['probe_type'])
        next unless items.any? { |w| w['id'] == signal['work_item_id'] }
        { **meta("invisible-#{i+1}"), 'work_item_id' => "#{@conversation.id}:#{signal['work_item_id']}", 'probe_type' => signal['probe_type'],
          'detail' => signal.dig('detail', 'value'), 'fact_status' => status_for(signal), 'evidence_refs' => refs_for(signal) }
      end
      @data['canonical_shadow_ai_signals'] = Array(@data['shadow_ai_signals']).each_with_index.map do |signal, i|
        invalid!('Invalid official AI flag') unless [nil, true, false].include?(signal['official'])
        { **meta("shadow-ai-#{i+1}"), 'participant_id' => @conversation.employee_id, 'tool' => signal.dig('tool', 'value'),
          'use_description' => signal.dig('use_description', 'value'), 'official' => signal['official'],
          'fact_status' => status_for(signal), 'evidence_refs' => refs_for(signal) }
      end
      @data['posture_signals'] = @data['canonical_shadow_ai_signals'].map do |signal|
        { **meta("posture-#{signal['id']}"), 'signal_type' => signal['official'] == false ? 'SHADOW_AI' : 'AI_TOOL_USE',
          'value' => signal['tool'], 'fact_status' => signal['fact_status'], 'evidence_refs' => signal['evidence_refs'] }
      end
      @data['evidence_references'] = @refs.values
      @data['context_policy'] = EmployeeContext.policy(@conversation).deep_stringify_keys
      @data['runtime'] = { 'stage_id' => 'EMPLOYEE_DISCOVERY', 'prompt_version' => @data['prompt_version'],
        'policy_version' => 'employee-discovery-context-v2.1', 'source_message_id' => @source&.id }
      @result
    end

    private

    def meta(id)
      prior = [@previous['role_profile'], *Array(@previous['canonical_work_items']), *Array(@previous['canonical_retired_work_items']), *Array(@previous['canonical_invisible_work_signals']),
        *Array(@previous['canonical_shadow_ai_signals']), *Array(@previous['evidence_references'])].compact.find { |record| record['id'] == "#{@conversation.id}:#{id}" }
      { 'id' => "#{@conversation.id}:#{id}", 'company_id' => @conversation.company_id,
        'version' => @data['revision'] + 1, 'created_at' => prior&.dig('created_at') || Time.current.iso8601,
        'updated_at' => Time.current.iso8601, 'created_by' => 'ai:employee_discovery_v2' }
    end

    def values(entries)
      invalid!('Invalid list of facts') unless entries.is_a?(Array) && entries.all? { |f| f.is_a?(Hash) && STATUSES.include?(f['fact_status']) && f['evidence'].present? }
      entries.filter_map { |f| f['value'] if f['fact_status'] == 'REPORTED' }
    end

    def walk_facts!(value)
      case value
      when Array then value.each { |v| walk_facts!(v) }
      when Hash
        if value.key?('fact_status')
          invalid!('Invalid employee fact status') unless STATUSES.include?(value['fact_status'])
          invalid!('Unlinked employee fact') unless value['evidence'].is_a?(Array) && value['evidence'].present?
          invalid!('Invalid fact value') unless value['value'].nil? || value['value'].is_a?(String)
          invalid!('Unknown fact has a value') if value['fact_status'] == 'UNKNOWN' && value['value']
          if value.key?('minimum')
            invalid!('Invalid effort basis') unless [nil, 'per_occurrence', 'per_day', 'per_week', 'per_month', 'per_quarter', 'per_year'].include?(value['basis'])
            a, b = value.values_at('minimum', 'maximum')
            if a || b
              numbers = EmployeeContext.evidence_numbers(value['quote'])
              invalid!('Invalid effort estimate') unless a.is_a?(Numeric) && b.is_a?(Numeric) && a.finite? && b.finite? && a >= 0 && b >= a && numbers.include?(a.to_f) && numbers.include?(b.to_f) && %w[minutes hours days].include?(value['unit'])
            end
          end
        end
        if value.key?('message_id') && value.key?('quote')
          evidence!(value)
        end
        value.each_value { |v| walk_facts!(v) }
      end
    end

    # Document 03: spoken answers are transcripts, whether recorded as a voice note
    # (audio) or transcribed live in the avatar interview (input_mode voice).
    def source_type(message)
      return 'TRANSCRIPT' if (message.raw_payload || {})['input_mode'] == 'voice'

      { 'audio' => 'TRANSCRIPT', 'image' => 'SCREENSHOT', 'document' => 'FILE' }.fetch(message.message_type, 'CHAT_MESSAGE')
    end

    def evidence!(anchor)
      message = @conversation.messages.where(direction: 'inbound', track: %w[discovery profiling]).where.not(message_type: 'system').find_by(id: anchor['message_id'])
      quote = anchor['quote']
      invalid!('Cross-context or fabricated evidence') unless message && quote.is_a?(String) && quote.present? && message.body.to_s.include?(quote) && EmployeeContext.redact(quote) == quote
      id = "evidence-#{@conversation.id}-#{message.id}-#{Digest::SHA256.hexdigest(quote)[0, 16]}"
      @refs[id] ||= { **meta(id), 'id' => id, 'evidence_id' => id,
        'source_type' => source_type(message), 'source_id' => message.id,
        'actor_id' => @conversation.employee_id, 'captured_at' => message.created_at.iso8601,
        'locator' => { 'conversation_id' => @conversation.id, 'message_id' => message.id }, 'excerpt_or_summary' => quote,
        'fact_status' => 'REPORTED', 'sensitivity' => 'CONFIDENTIAL',
        'access_policy' => { 'participant_id' => @conversation.employee_id, 'permitted_roles' => %w[employee consultant],
          'permitted_services' => %w[employee_discovery protected_synthesis task_intelligence deep_dive] },
        'language' => message.body.to_s.match?(/\p{Arabic}/) ? 'ar' : (@conversation.employee.preferred_language.presence || @conversation.company.locale),
        'integrity_metadata' => { 'sha256' => Digest::SHA256.hexdigest(message.body.to_s) }, 'retention_status' => 'ACTIVE' }
      anchor['evidence_id'] = id
    end

    def refs_for(value)
      case value
      when Array then value.flat_map { |v| refs_for(v) }.uniq
      when Hash then [value['evidence_id'], *value.values.flat_map { |v| refs_for(v) }].compact.uniq
      else []
      end
    end

    def status_for(value)
      statuses = current_statuses(value)
      statuses.include?('CONTRADICTED') ? 'CONTRADICTED' : statuses.include?('UNKNOWN') ? 'UNKNOWN' : 'REPORTED'
    end

    def current_statuses(value)
      case value
      when Array then value.flat_map { |v| current_statuses(v) }
      when Hash then [value['fact_status'], *value.except('history').values.flat_map { |v| current_statuses(v) }].compact
      else []
      end
    end

    def sized?(item)
      (item.dig('frequency', 'fact_status') == 'REPORTED' || answered_unknown?(item['frequency'])) && effort_complete?(item)
    end

    # An employee's explicit "I can't estimate this" completes sizing; the agent keeps
    # a follow-up requirement for it. A fact never supplied still blocks success.
    def answered_unknown?(fact)
      fact.is_a?(Hash) && fact['fact_status'] == 'UNKNOWN' && fact['evidence'].present?
    end

    def effort_complete?(item, seen = [])
      return false if seen.include?(item['id'])
      link = item['effort_inclusion']
      if link
        parent = @data['work_items'].find { |w| w['id'] == link['value'] }
        return link['fact_status'] == 'REPORTED' && parent && effort_complete?(parent, seen + [item['id']])
      end
      (item.dig('effort', 'fact_status') == 'REPORTED' && item.dig('effort', 'minimum').is_a?(Numeric) && item.dig('effort', 'maximum').is_a?(Numeric)) ||
        answered_unknown?(item['effort'])
    end

    def validate_effort_inclusions!
      items = @data['work_items'].index_by { |w| w['id'] }
      items.each_value do |item|
        link = item['effort_inclusion']
        next unless link
        explicit = link['quote'].to_s.match?(/\b(?:includ(?:e[sd]?|ing)|part of|covered by|counted (?:in|within)|within .*estimate)\b|مشمول|ضمن/i) &&
          !link['quote'].to_s.match?(/\b(?:not|never|isn't|aren't)\s+(?:already\s+)?(?:included|part of|covered)|\bseparate from\b|غير مشمول/i)
        invalid!('Unsupported effort inclusion') unless items.key?(link['value']) && link['value'] != item['id'] &&
          (explicit || confirmed_effort_scope?(item, items[link['value']], link))
        seen = [item['id']]
        while link && link['fact_status'] == 'REPORTED'
          parent = items[link['value']]
          invalid!('Invalid or cyclic effort inclusion') unless parent && !seen.include?(parent['id'])
          seen << parent['id']
          link = parent['effort_inclusion']
        end
      end
    end

    def confirmed_effort_scope?(item, parent, link)
      return false unless parent && link['scope_question'].is_a?(String) && link['quote'].to_s.strip.match?(/\A(?:yes|yeah|yep|yes,? correct|yes,? that's correct|correct|confirmed|نعم|نعم، صحيح|صحيح)[.!؟]*\z/i)
      answer = @conversation.messages.find_by(id: link['source_message_id'], direction: 'inbound')
      return false unless answer
      question = @conversation.messages.where(direction: 'outbound').where('id < ?', answer.id).order(:id).last
      text = question&.body.to_s
      text == link['scope_question'] && text.match?(/included|covered|مشمول|ضمن/i) &&
        [item, parent].all? do |w|
          description = w['description'] || {}
          [description, *Array(description['history'])].any? do |fact|
            fact['value'].present? && text.downcase.include?(fact['value'].downcase)
          end
        end
    end

    def validate_completion!(previous)
      return unless @result['completed']
      invalid!('Invalid outcome') unless %w[successful needs_follow_up employee_stopped].include?(@data['outcome'])
      if @data['outcome'] == 'employee_stopped'
        invalid!('Unsupported interview stop') unless @source&.body.to_s.strip.match?(/\A(?:end (?:the )?interview|stop interview|إنهاء المقابلة)[.!؟]*\z/i)
        return
      end
      shown = previous['presented_summary']
      confirmation = @data['confirmation']
      invalid!('Unconfirmed discovery completion') unless shown.is_a?(Hash) && confirmation.is_a?(Hash) &&
        shown['revision'] == @data['revision'] && confirmation['revision'] == @data['revision'] &&
        confirmation['summary_sha256'] == Digest::SHA256.hexdigest(shown['text'].to_s) &&
        Array(confirmation['evidence']).any? { |e| e['message_id'] == @source&.id }
      invalid!('Coverage does not permit success') if @data['outcome'] == 'successful' && !@data['coverage'].values.all?
    end
  end
end
