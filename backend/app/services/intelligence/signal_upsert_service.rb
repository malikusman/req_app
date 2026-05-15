# frozen_string_literal: true

module Intelligence
  class SignalUpsertService
    def self.call(company:, signals:, department: nil)
      new(company: company, signals: signals, department: department).call
    end

    def initialize(company:, signals:, department: nil)
      @company = company
      @signals = signals
      @department = department
    end

    def call
      @signals.each do |attrs|
        signal = CompanySignal.find_or_initialize_by(
          company: @company,
          signal_type: attrs[:signal_type],
          label: attrs[:label]
        )

        departments = (signal.departments + Array(@department)).compact.uniq
        now = Time.current

        if signal.new_record?
          signal.assign_attributes(
            strength: attrs[:strength],
            evidence_count: attrs[:evidence_count],
            departments: departments,
            first_seen_at: now,
            last_updated_at: now,
            strength_history: [{ "strength" => attrs[:strength], "at" => now.iso8601 }]
          )
          signal.save!
          TimelineRecorder.signal_detected!(company: @company, signal: signal)
        else
          new_strength = [signal.strength, attrs[:strength]].max
          signal.update!(
            evidence_count: signal.evidence_count + attrs[:evidence_count],
            departments: departments,
            last_updated_at: now
          )
          if new_strength > signal.strength + 0.05
            signal.record_strength!(new_strength)
            TimelineRecorder.signal_strengthened!(company: @company, signal: signal)
          end
        end
      end
    end
  end
end
