# frozen_string_literal: true

module Companies
  # Folds the onboarding form's answers into the facts the rest of the platform
  # reads: company_profile (through ProfileUpdater, so provenance is recorded),
  # the company's systems, and the engagement's planned departments.
  #
  # Only a field whose value actually changed is written, so re-saving the form
  # never relabels a fact the key user confirmed from their website as one they
  # typed.
  class OnboardingSync
    F = OnboardingFields

    def self.call(company:, answers:, actor: nil)
      new(company: company, answers: answers, actor: actor).call
    end

    def initialize(company:, answers:, actor:)
      @company = company
      @answers = (answers || {}).to_h.stringify_keys
      @actor = actor
    end

    def call
      ProfileUpdater.call(company: @company, profile_params: profile_params, known_systems: systems,
                          actor: @actor, only_changed: true)
      sync_planned_departments!
      @company
    end

    private

    def answered?(key) = @answers.key?(key)

    def profile_params
      params = {}
      if answered?("o01_industry")
        params["industry"] = unknown_or(@answers["o01_industry"]) do |label|
          label == F::OTHER ? "other" : F::INDUSTRIES[label]
        end
        detail = [@answers["o01_industry_other"], @answers["o01_industry_detail"]].map(&:to_s).map(&:strip)
                                                                                  .reject(&:empty?).first
        params["industry_detail"] = detail
      elsif answered?("o01_industry_detail")
        params["industry_detail"] = @answers["o01_industry_detail"]
      end
      params["size_band"] = unknown_or(@answers["o02_headcount"]) { |l| F::HEADCOUNTS[l] } if answered?("o02_headcount")
      if answered?("o03_hq_country")
        params["country"] = unknown_or(@answers["o03_hq_country"]) { |c| c }
        params["region"] = params["country"]
      end
      params["locations"] = unknown_or(@answers["o03_locations"]) { |t| split(t) } if answered?("o03_locations")
      if answered?("o04_business_model")
        params["business_model"] = mapped_list("o04_business_model", F::BUSINESS_MODELS, other_code: "OTHER")
      end
      params["products_services"] = @answers["o05_products_services"] if answered?("o05_products_services")
      params["org_departments"] = with_other("o06_departments") if answered?("o06_departments")
      params["customer_channels"] = mapped_list("o07_channels", F::CHANNELS, other_code: "OTHER") if answered?("o07_channels")
      params["data_storage"] = with_other("o09_data_storage") if answered?("o09_data_storage")
      params["current_ai_use"] = with_other("o10_ai_tools") if answered?("o10_ai_tools")
      params["security_constraints"] = constraints if answered?("o11_constraints")
      params
    end

    # O8 names kinds of system as well as products; only named products and the
    # client's own systems become CompanySystem rows. "Spreadsheets" is not a
    # system to integrate with.
    def systems
      return nil unless answered?("o08_systems")
      return nil if F.not_sure?(@answers["o08_systems"])

      picked = Array(@answers["o08_systems"]) - [F::OTHER, "Spreadsheets"]
      picked + split(@answers["o08_systems_other"])
    end

    def sync_planned_departments!
      engagement = @company.current_engagement
      return unless engagement && answered?("p1_departments")

      departments = F.not_sure?(@answers["p1_departments"]) ? [] : Array(@answers["p1_departments"])
      counts = @answers["p2_department_counts"].is_a?(Hash) ? @answers["p2_department_counts"] : {}
      planned = departments.map do |name|
        count = counts[name].to_s
        { "name" => name, "count" => count.match?(/\A\d+\z/) ? count.to_i : ProfileUpdater::UNKNOWN }
      end
      engagement.update!(planned_departments: planned) if planned != engagement.planned_departments
    end

    def unknown_or(value)
      return ProfileUpdater::UNKNOWN if F.not_sure?(value)
      return nil if value.blank?

      yield value
    end

    def mapped_list(key, mapping, other_code:)
      unknown_or(@answers[key]) do |labels|
        codes = Array(labels).map { |l| l == F::OTHER ? other_code : mapping[l] }.compact
        codes.uniq
      end
    end

    def with_other(key)
      unknown_or(@answers[key]) { |labels| (Array(labels) - [F::OTHER]) + split(@answers["#{key}_other"]) }
    end

    def constraints
      unknown_or(@answers["o11_constraints"]) do |labels|
        ((Array(labels) - [F::OTHER]) + split(@answers["o11_constraints_other"])).join("; ").presence
      end
    end

    def split(text)
      text.to_s.split(/[,\n;]/).map(&:strip).reject(&:empty?).uniq.first(20)
    end
  end
end
