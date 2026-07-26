# frozen_string_literal: true

require "net/http"
require "uri"

module Http
  # Simple GET that follows 301/302/303/307/308 with relative Location support.
  # Optional +validate+ callable is invoked for every hop URL (SSRF checks, etc.).
  class GetWithRedirects
    MAX_REDIRECTS = 5

    Result = Struct.new(:ok, :response, :final_url, :error, :status_code, keyword_init: true) do
      def body
        response&.body.to_s
      end

      def success?
        ok
      end
    end

    def self.call(url, headers: {}, open_timeout: 10, read_timeout: 20, max_redirects: MAX_REDIRECTS, validate: nil)
      new(
        url: url,
        headers: headers,
        open_timeout: open_timeout,
        read_timeout: read_timeout,
        max_redirects: max_redirects,
        validate: validate
      ).call
    end

    def initialize(url:, headers:, open_timeout:, read_timeout:, max_redirects:, validate:)
      @url = url.to_s
      @headers = headers
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @max_redirects = max_redirects
      @validate = validate
    end

    def call
      current = @url
      @max_redirects.times do
        uri = URI.parse(current)
        unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
          return Result.new(ok: false, final_url: current, error: "unsupported_scheme")
        end

        if @validate && !@validate.call(uri.to_s)
          return Result.new(ok: false, final_url: current, error: "unsafe_url")
        end

        response = request(uri)
        if response.is_a?(Net::HTTPRedirection)
          location = response["location"].to_s.strip
          return Result.new(ok: false, response: response, final_url: current, error: "redirect_missing_location", status_code: response.code.to_i) if location.blank?

          current = URI.join(uri, location).to_s
          next
        end

        unless response.is_a?(Net::HTTPSuccess)
          return Result.new(
            ok: false,
            response: response,
            final_url: current,
            error: "http_#{response.code}",
            status_code: response.code.to_i
          )
        end

        return Result.new(ok: true, response: response, final_url: current, status_code: response.code.to_i)
      end

      Result.new(ok: false, final_url: current, error: "too_many_redirects")
    rescue URI::InvalidURIError
      Result.new(ok: false, final_url: @url, error: "invalid_url")
    rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error
      Result.new(ok: false, final_url: current || @url, error: "timeout")
    rescue StandardError => e
      Result.new(ok: false, final_url: current || @url, error: e.message)
    end

    private

    def request(uri)
      Net::HTTP.start(
        uri.hostname,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: @open_timeout,
        read_timeout: @read_timeout
      ) do |http|
        req = Net::HTTP::Get.new(uri)
        @headers.each { |key, value| req[key] = value }
        http.request(req)
      end
    end
  end
end
