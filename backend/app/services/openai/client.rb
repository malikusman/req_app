# frozen_string_literal: true

require "net/http"
require "json"

module Openai
  class Client
    class Error < StandardError; end

    API_BASE = "https://api.openai.com/v1"

    def configured?
      api_key.present?
    end

    def transcribe_audio(file_path:, language: "en")
      return mock_transcript(language) unless configured?

      uri = URI("#{API_BASE}/audio/transcriptions")
      request = multipart_request(uri, {
        model: ENV.fetch("OPENAI_WHISPER_MODEL", "whisper-1"),
        language: language,
        file: File.open(file_path)
      })
      parse_json(request)["text"].to_s.strip
    end

    def describe_image(file_path:, language: "en")
      return mock_image_description(language) unless configured?

      data = Base64.strict_encode64(File.binread(file_path))
      mime = mime_for_path(file_path)
      body = {
        model: ENV.fetch("OPENAI_VISION_MODEL", "gpt-4o-mini"),
        messages: [{
          role: "user",
          content: [
            { type: "text", text: "Describe this work-related image for workflow discovery. Focus on tools, processes, and pain points. Language: #{language}." },
            { type: "image_url", image_url: { url: "data:#{mime};base64,#{data}" } }
          ]
        }],
        max_tokens: 500
      }
      post_json("#{API_BASE}/chat/completions", body).dig("choices", 0, "message", "content").to_s.strip
    end

    def embedding(text)
      return Array.new(1536, 0.0) unless configured?

      body = {
        model: ENV.fetch("OPENAI_EMBEDDING_MODEL", "text-embedding-3-small"),
        input: text
      }
      post_json("#{API_BASE}/embeddings", body).dig("data", 0, "embedding")
    end

    def summarize_document(text, language: "en")
      return mock_document_summary(text, language) unless configured?

      body = {
        model: ENV.fetch("OPENAI_MODEL", "gpt-4o-mini"),
        messages: [{
          role: "user",
          content: <<~PROMPT
            Summarize workflows, tools, and friction points from this document for an enterprise discovery platform.
            Respond in #{language} as JSON: {"summary":"...","workflows":["..."],"friction_points":["..."]}
            Document:
            #{text.truncate(12_000)}
          PROMPT
        }],
        response_format: { type: "json_object" }
      }
      content = post_json("#{API_BASE}/chat/completions", body).dig("choices", 0, "message", "content")
      JSON.parse(content)
    rescue JSON::ParserError
      { "summary" => content.to_s.truncate(500), "workflows" => [], "friction_points" => [] }
    end

    private

    def api_key
      ENV["OPENAI_API_KEY"].presence
    end

    def post_json(url, body)
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 120
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{api_key}"
      request["Content-Type"] = "application/json"
      request.body = body.to_json
      parse_json(http.request(request))
    end

    def multipart_request(uri, fields)
      boundary = "----RubyMultipart#{SecureRandom.hex(8)}"
      body = build_multipart_body(boundary, fields)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 120
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{api_key}"
      request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
      request.body = body
      parse_json(http.request(request))
    ensure
      fields[:file]&.close
    end

    def build_multipart_body(boundary, fields)
      lines = []
      fields.each do |name, value|
        if value.is_a?(File)
          lines << "--#{boundary}\r\n"
          lines << "Content-Disposition: form-data; name=\"#{name}\"; filename=\"#{File.basename(value.path)}\"\r\n"
          lines << "Content-Type: application/octet-stream\r\n\r\n"
          lines << value.read
          lines << "\r\n"
          value.rewind
        else
          lines << "--#{boundary}\r\n"
          lines << "Content-Disposition: form-data; name=\"#{name}\"\r\n\r\n"
          lines << value.to_s
          lines << "\r\n"
        end
      end
      lines << "--#{boundary}--\r\n"
      lines.join
    end

    def parse_json(response)
      body = JSON.parse(response.body) rescue {}
      unless response.is_a?(Net::HTTPSuccess)
        raise Error, body.dig("error", "message") || response.message
      end
      body
    end

    def mock_transcript(language)
      {
        "en" => "[Voice note] I spend mornings reconciling invoices in Excel before uploading to SAP.",
        "es" => "[Nota de voz] Paso las mañanas conciliando facturas en Excel antes de subirlas a SAP.",
        "fr" => "[Message vocal] Je passe mes matinées à rapprocher des factures dans Excel.",
        "de" => "[Sprachnotiz] Ich verbringe meine Morgen mit dem Abgleich von Rechnungen in Excel."
      }.fetch(language, "[Voice note] I described my daily workflow and main tools.")
    end

    def mock_image_description(language)
      {
        "en" => "[Image] Screenshot of an Excel spreadsheet used for invoice tracking with manual approval columns.",
        "es" => "[Imagen] Captura de una hoja de Excel para seguimiento de facturas con columnas de aprobación manual.",
        "fr" => "[Image] Capture d'écran d'une feuille Excel pour le suivi des factures.",
        "de" => "[Bild] Screenshot einer Excel-Tabelle zur Rechnungsverfolgung."
      }.fetch(language, "[Image] Work-related screenshot showing tools and processes.")
    end

    def mime_for_path(path)
      ext = File.extname(path).downcase
      {
        ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg", ".png" => "image/png",
        ".gif" => "image/gif", ".webp" => "image/webp"
      }.fetch(ext, "image/jpeg")
    end

    def mock_document_summary(text, language)
      snippet = text.to_s.gsub(/\s+/, " ").strip.truncate(200)
      {
        "summary" => "Document describes operational workflows#{snippet.present? ? ": #{snippet}" : "."}",
        "workflows" => ["Documented process steps"],
        "friction_points" => ["Manual handoffs", "Spreadsheet dependency"]
      }
    end
  end
end
