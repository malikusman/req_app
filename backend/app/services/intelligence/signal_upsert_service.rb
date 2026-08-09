# frozen_string_literal: true

module Intelligence
  class SignalUpsertService
    def self.call(company:, signals:, department: nil, reconcile_stale: false)
      new(company: company, signals: signals, department: department, reconcile_stale: reconcile_stale).call
    end

    def initialize(company:, signals:, department: nil, reconcile_stale: false)
      @company = company
      @signals = signals
      @department = department
      @reconcile_stale = reconcile_stale
    end

    def call
      seen_ids = []

      @signals.each do |attrs|
        signal = CompanySignal.find_or_initialize_by(
          company: @company,
          signal_type: attrs[:signal_type],
          label: attrs[:label]
        )

        departments = canonical_departments(signal.departments + Array(@department))
        now = Time.current
        new_strength = attrs[:strength].to_f
        new_evidence = attrs[:evidence_count].to_i

        if signal.new_record?
          signal.assign_attributes(
            strength: new_strength,
            evidence_count: new_evidence,
            departments: departments,
            first_seen_at: now,
            last_updated_at: now,
            strength_history: [{ "strength" => new_strength, "at" => now.iso8601 }],
            metadata: metadata_from_attrs(attrs)
          )
          signal.save!
          TimelineRecorder.signal_detected!(company: @company, signal: signal)
        else
          previous_strength = signal.strength.to_f
          history = signal.strength_history
          if new_strength > previous_strength + 0.05
            history = history + [{ "strength" => previous_strength, "at" => now.iso8601 }]
          end

          signal.update!(
            evidence_count: new_evidence,
            strength: new_strength,
            departments: departments,
            last_updated_at: now,
            strength_history: history,
            metadata: metadata_from_attrs(attrs),
            status: new_strength >= 0.7 ? "confirmed" : signal.status
          )

          if new_strength > previous_strength + 0.05
            TimelineRecorder.signal_strengthened!(company: @company, signal: signal)
          end
        end

        seen_ids << signal.id
      end

      if @reconcile_stale
        @company.company_signals.where.not(id: seen_ids).find_each(&:destroy!)
      end

      seen_ids
    end

    private

    # Dedupe departments case-insensitively (keeping first-seen casing) so
    # "Finance" and "finance" don't both surface in the report.
    def canonical_departments(list)
      Array(list).map { |d| d.to_s.strip }.reject(&:blank?).each_with_object({}) do |dept, acc|
        acc[dept.downcase] ||= dept
      end.values
    end

    def metadata_from_attrs(attrs)
      {
        "multimodal_evidence" => Array(attrs[:multimodal_evidence]).map { |item|
          item.respond_to?(:stringify_keys) ? item.stringify_keys : item
        }.first(Intelligence::SignalExtractor::MAX_EVIDENCE),
        "source_excerpts" => Array(attrs[:source_excerpts]).map { |item|
          item.respond_to?(:stringify_keys) ? item.stringify_keys : item
        }.first(Intelligence::SignalExtractor::MAX_EVIDENCE)
      }
    end
  end
end
