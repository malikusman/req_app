# frozen_string_literal: true

require "nokogiri"
require "resolv"
require "ipaddr"
require "uri"

module Companies
  # Fetches a company's public website safely: only public http(s) hosts (no
  # private, loopback, link-local or metadata addresses, checked on every
  # redirect), a size cap, a timeout, and a browser-like retry when a site turns
  # the default client away.
  #
  # #pages reads the home page plus the few pages a website pre-fill needs —
  # about, products or services, contact, locations, careers (Doc 07 §5.2) — on
  # the same site, English or Arabic. Each page keeps its header and footer text
  # apart from the body: that is where addresses, phone numbers and social links
  # usually are.
  class WebsiteFetcher
    class Unreachable < StandardError; end

    MAX_BYTES = 500_000
    FETCH_TIMEOUT = 12
    MAX_EXTRA_PAGES = 5
    BODY_LIMIT = 6_000
    CHROME_LIMIT = 1_500
    TOTAL_LIMIT = 24_000

    PRODUCT_HEADERS = {
      "User-Agent" => "MjadiCompanyResearch/1.0 (+https://mjadi.ai)",
      "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      "Accept-Language" => "en-US,en;q=0.9,ar;q=0.8"
    }.freeze

    BROWSER_HEADERS = {
      "User-Agent" => "Mozilla/5.0 (compatible; MjadiCompanyResearch/1.0; +https://mjadi.ai) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
      "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      "Accept-Language" => "en-US,en;q=0.9,ar;q=0.8"
    }.freeze

    # The pages worth reading, most useful first. Matched against a link's path
    # and its text, in English and Arabic.
    PAGE_KINDS = [
      /about|who-we-are|company|our-story|من نحن|عن الشركة/i,
      /product|service|solution|what-we-do|منتجات|خدمات|حلول/i,
      /contact|location|branch|store-locator|اتصل|تواصل|فروع|مواقع/i,
      /career|jobs|join-us|وظائف|التوظيف/i
    ].freeze

    SKIPPED_FILES = /\.(pdf|jpe?g|png|gif|webp|svg|zip|docx?|xlsx?|mp4)\z/i

    Page = Struct.new(:url, :text, :chrome, keyword_init: true)

    def self.safe_public_http_url?(url)
      uri = URI.parse(url)
      return false unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
      return false if uri.host.blank?

      ips = Resolv.getaddresses(uri.host)
      return false if ips.empty?

      ips.none? { |ip| private_or_loopback?(ip) }
    rescue URI::InvalidURIError, Resolv::ResolvError
      false
    end

    def self.private_or_loopback?(ip_str)
      ip = IPAddr.new(ip_str)
      return true if ip.loopback? || ip.private?
      return true if ip.respond_to?(:link_local?) && ip.link_local?

      # IPv4 link-local / CGNAT / metadata
      return true if ip.ipv4? && (ip.to_s.start_with?("169.254.") || ip.to_s.start_with?("100.64."))

      false
    rescue IPAddr::InvalidAddressError
      true
    end

    # One page's HTML: { html:, error:, status_code:, final_url: }.
    def fetch_html(url)
      return { html: nil, error: "unsafe_url" } unless self.class.safe_public_http_url?(url)

      result = get_with_headers(url, PRODUCT_HEADERS)
      result = get_with_headers(url, BROWSER_HEADERS) if !result.success? && blocked_status?(result.status_code)

      unless result.success?
        error = blocked_status?(result.status_code) ? "blocked_by_site" : result.error.presence || "fetch_failed"
        return { html: nil, error: error, status_code: result.status_code, final_url: result.final_url }
      end

      body = result.body
      body = body.byteslice(0, MAX_BYTES) if body.bytesize > MAX_BYTES
      { html: body, error: nil, status_code: result.status_code, final_url: result.final_url }
    end

    # The home page and the pages worth reading from it. Raises Unreachable when
    # the home page can't be fetched at all; other pages that fail are skipped.
    def pages(url)
      home = fetch_html(url)
      raise Unreachable, home[:error] if home[:html].blank?

      base = home[:final_url].presence || url
      collected = [page_from(base, home[:html])]
      total = collected.first.text.length + collected.first.chrome.length

      candidate_links(base, home[:html]).each do |link|
        break if collected.size > MAX_EXTRA_PAGES || total >= TOTAL_LIMIT

        fetched = fetch_html(link)
        next if fetched[:html].blank?

        page = page_from(fetched[:final_url].presence || link, fetched[:html])
        next if page.text.blank? || collected.any? { |p| p.url == page.url }

        collected << page
        total += page.text.length + page.chrome.length
      end
      collected
    end

    private

    def page_from(url, html)
      doc = Nokogiri::HTML(html)
      doc.css("script, style, noscript, svg, iframe").remove
      chrome = doc.css("header, footer").map(&:text).join(" ")
      doc.css("nav, header, footer").remove
      body = doc.at("main")&.text || doc.at("body")&.text || doc.text
      Page.new(url: url, text: squish(body).truncate(BODY_LIMIT), chrome: squish(chrome).truncate(CHROME_LIMIT))
    end

    # Same-site links whose path or text says they are one of PAGE_KINDS, the
    # most useful kind first, one page per kind before a second of any.
    def candidate_links(base, html)
      base_uri = URI.parse(base)
      links = Nokogiri::HTML(html).css("a[href]").filter_map do |a|
        href = a["href"].to_s.strip
        next if href.empty? || href.start_with?("#", "mailto:", "tel:", "javascript:")

        uri = URI.join(base_uri, encode_href(href))
        next unless uri.is_a?(URI::HTTP) && same_site?(uri.host, base_uri.host)
        next if uri.path.to_s.match?(SKIPPED_FILES)

        uri.fragment = nil
        [uri.to_s, "#{URI.decode_www_form_component(uri.path.to_s)} #{a.text}"]
      rescue URI::Error, ArgumentError
        nil
      end.uniq(&:first)

      by_kind = PAGE_KINDS.map { |pattern| links.select { |_, label| label.match?(pattern) }.map(&:first) }
      ordered = []
      by_kind.map(&:dup).then do |queues|
        ordered << queues.filter_map(&:shift) until queues.all?(&:empty?)
      end
      (ordered.flatten.uniq - [base, "#{base}/"]).first(MAX_EXTRA_PAGES)
    end

    # Arabic sites often link with raw Arabic paths ("/من-نحن"), which URI won't
    # parse until the non-ASCII characters and spaces are percent-encoded.
    def encode_href(href)
      href.gsub(/[^\x21-\x7E]/) { |char| char.bytes.map { |b| format("%%%02X", b) }.join }
    end

    def same_site?(host, base_host)
      host.to_s.downcase.delete_prefix("www.") == base_host.to_s.downcase.delete_prefix("www.")
    end

    def squish(text)
      text.to_s.gsub(/\s+/, " ").strip
    end

    def get_with_headers(url, headers)
      Http::GetWithRedirects.call(
        url,
        headers: headers,
        open_timeout: FETCH_TIMEOUT,
        read_timeout: FETCH_TIMEOUT,
        validate: self.class.method(:safe_public_http_url?)
      )
    end

    def blocked_status?(code)
      [401, 403, 429].include?(code.to_i)
    end
  end
end
