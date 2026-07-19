# frozen_string_literal: true

module MarketIntel
  class MatchAndNotifyService
    def self.call(limit_candidates: 50)
      new(limit_candidates: limit_candidates).call
    end

    def initialize(limit_candidates:)
      @limit_candidates = limit_candidates
    end

    def call
      sent = 0
      candidates = CatalogCandidate.emailable.order(analyzed_at: :desc).limit(@limit_candidates)

      EmployeeValuePreference.opted_in.find_each do |preference|
        employee = preference.employee
        next if employee.email.blank?
        next if EmployeeMarketAlert.sent_count_this_month(employee.id) >= max_per_month

        candidates.each do |candidate|
          break if EmployeeMarketAlert.sent_count_this_month(employee.id) >= max_per_month
          next if EmployeeMarketAlert.exists?(employee_id: employee.id, catalog_candidate_id: candidate.id)

          fit = MarketIntel::EmployeeFitService.call(employee: employee, candidate: candidate)
          next unless fit[:qualifies]

          alert = EmployeeMarketAlert.create!(
            employee: employee,
            company: employee.company,
            catalog_candidate: candidate,
            fit_score: fit[:fit_score],
            fit_rationale: fit[:fit_rationale],
            period_month: EmployeeMarketAlert.period_month_for,
            status: "draft",
            email_body: build_email_body(employee, candidate, fit)
          )
          MarketIntel::SendAlertService.call(alert: alert)
          sent += 1 if alert.reload.status == "sent"
        rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid, ArgumentError
          next
        rescue StandardError => e
          Rails.logger.warn("[MarketIntel::MatchAndNotify] employee=#{employee.id} candidate=#{candidate.id}: #{e.message}")
          next
        end
      end

      { sent: sent, candidates_considered: candidates.size }
    end

    private

    def max_per_month
      ENV.fetch("AI_MARKET_ALERT_MAX_PER_MONTH", "2").to_i.clamp(1, 8)
    end

    def build_email_body(employee, candidate, fit)
      tools = Array(employee.profile_data["primary_tools"]).first(5)
      {
        "headline" => "A #{candidate.entity_type} that may help your work",
        "greeting" => "Hi #{employee.display_name.presence || 'there'}",
        "role_line" => [employee.role_title, employee.department].compact.join(" · "),
        "tools" => tools,
        "item_name" => candidate.name,
        "item_type" => candidate.entity_type,
        "summary" => candidate.summary.presence || candidate.description,
        "why" => fit[:fit_rationale],
        "source_url" => candidate.source_url,
        "source_name" => candidate.provenance&.dig("catalog_source_name")
      }
    end
  end
end
