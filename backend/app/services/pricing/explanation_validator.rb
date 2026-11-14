# frozen_string_literal: true

module Pricing
  # Checks P24's reply before anything uses it (P24 §8–9). Any one of these is
  # a critical failure, and the reply is dropped for the template:
  #
  # - an amount that isn't one the platform computed — invented, adjusted or
  #   rounded
  # - anything internal in the client's text: margin, cost, hours, rates, the
  #   floor
  # - discount, negotiation or price-change language anywhere
  # - no risks named when the platform flagged some
  # - methodology or AI vocabulary in the client's text
  class ExplanationValidator
    ADMIN_STRINGS = %w[headline effort_basis comparables_note margin_note recommendation_note].freeze
    CLIENT_LISTS = %w[what_is_included what_is_not_included].freeze
    CLIENT_STRINGS = %w[participants_and_departments deliverable additional_participants what_happens_next validity].freeze
    CONFIDENCE = %w[HIGH MEDIUM LOW].freeze

    INTERNAL_TERMS = /margin|\bcosts?\b|cost basis|\bhours?\b|rate card|\bfloor\b|internal|override|comparable|consultant time/i
    NEGOTIATION = /discount|negotia|could go (?:down|lower|to)|reduc\w* the (?:fee|price)|lower (?:fee|price)|push back|flexib|best price|special price/i
    JARGON = /\bAI\b|artificial intelligence|\bLLM\b|language model|algorithm|deep[- ]dives?|synthesis|discovery engine/i
    NO_RISK = /\Ano (?:significant |material )?risks?\b/i
    AMOUNT = /(?:[A-Z]{3})\s?(\d[\d,]*(?:\.\d+)?)/

    def initialize(reply, quote)
      @reply = reply
      @quote = quote
    end

    # [admin_view, client_scope] when the reply passes, otherwise raises with
    # the reason.
    def call
      admin = section("administrator_view")
      client = section("client_scope_statement")
      check_shape!(admin, client)
      check_amounts!(admin, client)
      check_client_text!(client)
      check_language!(admin, client)
      check_risks!(admin)
      [admin.slice(*ADMIN_STRINGS, "derivation", "confidence", "what_could_make_this_wrong"),
       client.slice(*CLIENT_LISTS, *CLIENT_STRINGS)]
    end

    class Invalid < StandardError; end

    private

    def section(key)
      value = @reply.is_a?(Hash) ? @reply[key] : nil
      raise Invalid, "missing #{key}" unless value.is_a?(Hash)

      value
    end

    def check_shape!(admin, client)
      raise Invalid, "derivation must be a list" unless admin["derivation"].is_a?(Array) && admin["derivation"].any?
      raise Invalid, "confidence must be HIGH, MEDIUM or LOW" unless CONFIDENCE.include?(admin["confidence"])
      raise Invalid, "risks must be a list" unless admin["what_could_make_this_wrong"].is_a?(Array)

      (ADMIN_STRINGS).each { |k| raise Invalid, "#{k} missing" unless admin[k].is_a?(String) }
      CLIENT_LISTS.each do |k|
        raise Invalid, "#{k} must be a list of sentences" unless client[k].is_a?(Array) && client[k].any? && client[k].all?(String)
      end
      CLIENT_STRINGS.each { |k| raise Invalid, "#{k} missing" unless client[k].is_a?(String) && client[k].present? }
    end

    def check_amounts!(admin, client)
      allowed = Stage1Context.allowed_amounts(@quote)
      texts(admin, client).each do |text|
        text.scan(AMOUNT).flatten.each do |figure|
          amount = BigDecimal(figure.delete(","))
          raise Invalid, "an amount the platform didn't compute: #{figure}" unless allowed.include?(amount)
        end
      end
    end

    def check_client_text!(client)
      text = texts({}, client).join(" ")
      raise Invalid, "internal terms in the client's text" if text.match?(INTERNAL_TERMS)
      raise Invalid, "methodology or AI vocabulary in the client's text" if text.match?(JARGON)
    end

    def check_language!(admin, client)
      raise Invalid, "discount or negotiation language" if texts(admin, client).join(" ").match?(NEGOTIATION)
    end

    def check_risks!(admin)
      signals = Array(@quote.estimate["risk_signals"])
      named = admin["what_could_make_this_wrong"].reject { |r| r.to_s.match?(NO_RISK) }
      return if signals.empty? || named.any?

      raise Invalid, "no risks named though the platform flagged #{signals.size}"
    end

    def texts(admin, client)
      strings = []
      walk = lambda do |value|
        case value
        when String then strings << value
        when Array then value.each(&walk)
        when Hash then value.each_value(&walk)
        end
      end
      walk.call(admin)
      walk.call(client)
      strings
    end
  end
end
