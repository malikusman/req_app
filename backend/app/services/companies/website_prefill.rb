# frozen_string_literal: true

module Companies
  # Reads the client's website and proposes onboarding values for them to confirm
  # (Doc 07 §5, prompt P01). The model only proposes; code decides what is kept:
  #
  # - only the eight fields a website can answer, with their allowed values;
  # - only with evidence — a short excerpt from a page that was actually fetched;
  # - never headcount, revenue, budget or readiness, whatever the model returns;
  # - departments, systems and AI tools only when the site shows them clearly.
  #
  # What survives is stored as PROPOSED candidates. Nothing reads them as fact:
  # only the onboarding screen shows them, and only the key user's confirmation
  # writes the profile. Anything that goes wrong — no website, a site that won't
  # load, no model, a reply that isn't usable — leaves the plain form, without
  # comment to the client (Doc 07 §5.5).
  class WebsitePrefill
    BUSINESS_MODELS = %w[B2B B2C WHOLESALE RETAIL DISTRIBUTION MANUFACTURING SERVICES PROJECT SUBSCRIPTION MARKETPLACE
                         OTHER].freeze
    CHANNELS = %w[EMAIL PHONE WHATSAPP WEBSITE ONLINE_STORE SOCIAL_MEDIA MARKETPLACES IN_PERSON OTHER].freeze
    ENUMS = { "business_model" => BUSINESS_MODELS, "customer_channels" => CHANNELS }.freeze
    LIST_FIELDS = %w[locations business_model customer_channels departments core_systems ai_tools].freeze
    # Rarely visible on a website; kept only when the site shows them plainly (P01 §5.1).
    STRICT_FIELDS = %w[departments core_systems ai_tools].freeze
    # Never inferred from a website (Doc 07 §5.3, P01 rule 2).
    FORBIDDEN = /\b(head\s*count|employees?|staff of|workforce|revenue|turnover|budget|readiness|maturity)\b/i
    EXCERPT_WORDS = 25
    QUOTE_OVERLAP = 0.7

    # pages: already-read pages, for a demo or replay against a saved site; normally
    # the website is fetched.
    def self.call(engagement:, pages: nil)
      new(engagement: engagement, pages: pages).call
    end

    def initialize(engagement:, pages: nil)
      @engagement = engagement
      @company = engagement.company
      @given_pages = pages
    end

    def call
      website = @company.website_url.to_s.strip
      return finish!("empty", "no_website") if website.blank?
      return finish!("empty", "model_off") unless Llm::Prefill.enabled? && client.configured?
      return finish!("failed", "model_unavailable") if OpenaiCircuitBreaker.open?

      @engagement.update!(prefill_status: "running", prefill_error: nil)
      pages = @given_pages || WebsiteFetcher.new.pages(website)
      parsed = extract(website, pages)
      return finish!("empty", "unusable_reply") unless parsed.is_a?(Hash)
      # The website changed while we were reading it: these values describe the old one.
      return @engagement if @company.reload.website_url.to_s.strip != website

      candidates = validated(parsed["candidates"], pages)
      store!(candidates, website, parsed)
      finish!(candidates.any? ? "done" : "empty", candidates.any? ? nil : "nothing_usable")
    rescue WebsiteFetcher::Unreachable
      raise # the job tries once more, later
    rescue StandardError => e
      Rails.logger.warn("[WebsitePrefill] engagement=#{@engagement.id} #{e.class}: #{e.message}")
      finish!("failed", e.class.name)
    end

    private

    def client
      @client ||= Openai::Client.new
    end

    # One retry for a reply that isn't valid JSON (P01 §9), then give up quietly.
    def extract(website, pages)
      attempts = 0
      begin
        attempts += 1
        client.website_prefill(
          company_name: @company.display_name.presence || @company.name,
          website: website,
          display_language: display_language,
          pages: pages.map(&:to_h)
        )
      rescue JSON::ParserError
        retry if attempts < 2
        nil
      end
    end

    # The key user's language isn't known until they answer A4, so the first of the
    # engagement's languages.
    def display_language
      { "ar" => "Arabic", "en" => "English" }.fetch(@engagement.languages.first.to_s, "English")
    end

    def validated(raw, pages)
      seen = {}
      Array(raw).filter_map do |item|
        next unless item.is_a?(Hash)

        field = item["field"].to_s
        next unless PrefillCandidate::FIELDS.include?(field)
        next if seen[field]

        confidence = item["confidence"].to_s.upcase
        next unless PrefillCandidate::CONFIDENCES.include?(confidence)
        next if STRICT_FIELDS.include?(field) && confidence == "LOW"

        source = item["source_url"].to_s.strip
        page = pages.find { |p| p.url == source || p.url.chomp("/") == source.chomp("/") }
        next unless page

        excerpt = item["evidence_excerpt"].to_s.squish.split.first(EXCERPT_WORDS).join(" ")
        next unless quoted_from?(excerpt, page)

        value = clean_value(field, item["value"])
        next if value.blank?

        display = item["display_text"].to_s.squish.truncate(300).presence
        next if [field, value, display].flatten.compact.join(" ").match?(FORBIDDEN)

        seen[field] = true
        { field: field, value: value, display_text: display, confidence: confidence, source_url: source,
          excerpt: excerpt }
      end
    end

    # The excerpt must be the page's own words, not the model's reasoning about
    # it ("the showrooms imply in-person sales"). Most of its words have to appear
    # on the cited page; a little paraphrase or trimming is tolerated.
    def quoted_from?(excerpt, page)
      words = significant_words(excerpt)
      return false if words.empty?

      on_page = significant_words("#{page.text} #{page.chrome}").to_set
      words.count { |w| on_page.include?(w) } >= (words.size * QUOTE_OVERLAP).ceil
    end

    def significant_words(text)
      text.to_s.downcase.scan(/[[:alnum:]]+/).select { |w| w.length > 2 }
    end

    def clean_value(field, raw)
      if LIST_FIELDS.include?(field)
        list = Array(raw).map { |v| v.to_s.squish.truncate(120) }.reject(&:blank?).uniq.first(20)
        list = list.map(&:upcase) & ENUMS[field] if ENUMS[field]
        list
      else
        raw.is_a?(Array) ? nil : raw.to_s.squish.truncate(400)
      end
    end

    # New proposals replace the ones nobody has acted on yet; candidates the key
    # user confirmed, corrected or rejected stay, as the record of that decision.
    def store!(candidates, website, parsed)
      now = Time.current
      PrefillCandidate.transaction do
        @engagement.prefill_candidates.proposed.delete_all
        candidates.each do |c|
          @engagement.prefill_candidates.create!(
            company: @company, target_field: c[:field], value: c[:value], display_text: c[:display_text],
            confidence: c[:confidence], source_url: c[:source_url], evidence_excerpt: c[:excerpt],
            website_url: website, prompt_version: Openai::Client::WEBSITE_PREFILL_PROMPT_VERSION, extracted_at: now
          )
        end
        entity = parsed["entity_check"].is_a?(Hash) ? parsed["entity_check"] : {}
        note = entity["website_describes"] == "GROUP" ? entity["note"].to_s.squish.truncate(300).presence || "group" : nil
        @engagement.update!(prefill_entity_note: note)
      end
    end

    def finish!(status, error)
      @engagement.update!(prefill_status: status, prefill_error: error, prefill_finished_at: Time.current)
      @engagement
    end
  end
end
