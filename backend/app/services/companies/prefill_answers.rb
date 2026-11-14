# frozen_string_literal: true

module Companies
  # Turns a website proposal into the onboarding form's own answers, by rule, so
  # confirming one fills the same fields the key user would have filled by hand
  # (Doc 07 §5.3 → §6). Values the form has no option for go under "Other".
  class PrefillAnswers
    F = OnboardingFields

    # Words in the website's description of the business → the form's industry.
    # First match wins; nothing matching leaves "Other" with the website's words.
    INDUSTRY_WORDS = [
      [/wholesal|distribut|trading/i, "Wholesale & distribution"],
      [/retail|e-?commerce|online store/i, "Retail & e-commerce"],
      [/manufactur|factory|production/i, "Manufacturing"],
      [/logistic|freight|shipping|transport|courier/i, "Logistics & transport"],
      [/construct|engineering|contracting/i, "Construction & engineering"],
      [/real estate|property|properties/i, "Real estate"],
      [/consult|professional services|legal|law firm|accounting|audit/i, "Professional services"],
      [/financ|insurance|bank/i, "Financial services & insurance"],
      [/health|medical|clinic|hospital|pharma/i, "Healthcare"],
      [/hospitality|hotel|restaurant|catering/i, "Hospitality & food"],
      [/education|school|university|training/i, "Education"],
      [/software|technology|\bIT\b|digital/i, "Technology & software"],
      [/energy|utilit|oil|gas|solar/i, "Energy & utilities"],
      [/automotive|vehicle|\bcars?\b/i, "Automotive"],
      [/media|marketing|advertis|publishing/i, "Media & marketing"],
      [/government|public sector|ministry/i, "Government & public sector"],
      [/agricultur|farm/i, "Agriculture & food production"]
    ].freeze

    # Which company_profile key each proposal ends up in.
    PROFILE_KEYS = {
      "industry" => "industry", "products_services" => "products_services", "locations" => "locations",
      "business_model" => "business_model", "customer_channels" => "customer_channels",
      "departments" => "org_departments", "ai_tools" => "current_ai_use"
    }.freeze

    def self.for(candidate)
      new(candidate).answers
    end

    def initialize(candidate)
      @field = candidate.target_field
      @value = candidate.value
      @display = candidate.display_text.to_s
    end

    def answers
      case @field
      when "industry" then industry
      when "products_services" then { "o05_products_services" => @value.to_s.truncate(400) }
      when "locations" then { "o03_locations" => Array(@value).join(", ").truncate(300) }
      when "business_model" then coded("o04_business_model", F::BUSINESS_MODELS.invert)
      when "customer_channels" then coded("o07_channels", F::CHANNELS.invert)
      when "departments" then labelled("o06_departments", F::DEPARTMENTS)
      when "core_systems" then labelled("o08_systems", F::SYSTEMS)
      when "ai_tools" then labelled("o10_ai_tools", F::AI_TOOLS - [F::NO_AI])
      else {}
      end
    end

    private

    def industry
      text = "#{@value} #{@display}"
      label = INDUSTRY_WORDS.find { |pattern, _| text.match?(pattern) }&.last
      detail = @display.presence || @value.to_s
      answers = { "o01_industry" => label || F::OTHER, "o01_industry_detail" => detail.truncate(120) }
      answers["o01_industry_other"] = @value.to_s.truncate(F::OTHER_TEXT_MAX_LENGTH) unless label
      answers
    end

    def coded(key, labels_by_code)
      picked = Array(@value).filter_map { |code| code == "OTHER" ? F::OTHER : labels_by_code[code] }.uniq
      { key => picked }
    end

    # Names the form lists become those options; the rest go under Other.
    def labelled(key, options)
      by_name = options.index_by(&:downcase)
      known, others = Array(@value).partition { |name| by_name.key?(name.to_s.downcase) }
      picked = known.map { |name| by_name[name.to_s.downcase] }
      answers = { key => others.any? ? picked + [F::OTHER] : picked }
      answers["#{key}_other"] = others.join(", ").truncate(F::OTHER_TEXT_MAX_LENGTH) if others.any?
      answers
    end
  end
end
