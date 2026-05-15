# frozen_string_literal: true

require "net/http"
require "securerandom"

module Reports
  class PdfGenerator
    class Error < StandardError; end

    def self.call(html:)
      new(html: html).call
    end

    def initialize(html:)
      @html = html
    end

    def call
      url = ENV.fetch("GOTENBERG_URL", "http://gotenberg:3000")
      uri = URI("#{url.chomp('/')}/forms/chromium/convert/html")

      boundary = "----RubyFormBoundary#{SecureRandom.hex(8)}"
      body = build_multipart(boundary)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.read_timeout = 120

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
      request.body = body

      response = http.request(request)
      raise Error, "Gotenberg failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      response.body
    rescue Error, Errno::ECONNREFUSED, SocketError => e
      Rails.logger.warn("[PDF] Gotenberg unavailable (#{e.message}), storing HTML fallback")
      @html
    end

    private

    def build_multipart(boundary)
      parts = []
      parts << "--#{boundary}\r\n"
      parts << "Content-Disposition: form-data; name=\"files\"; filename=\"index.html\"\r\n"
      parts << "Content-Type: text/html\r\n\r\n"
      parts << @html
      parts << "\r\n--#{boundary}--\r\n"
      parts.join
    end
  end
end
