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
      ensure_configured_or_mock!("OpenAI")
      return mock_transcript(language) unless configured?

      uri = URI("#{API_BASE}/audio/transcriptions")
      # multipart_request already returns the parsed JSON body
      multipart_request(uri, {
        model: ENV.fetch("OPENAI_WHISPER_MODEL", "whisper-1"),
        language: language,
        file: File.open(file_path)
      })["text"].to_s.strip
    end

    def describe_image(file_path:, language: "en")
      ensure_configured_or_mock!("OpenAI")
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
      ensure_configured_or_mock!("OpenAI")
      return Array.new(1536, 0.0) unless configured?

      body = {
        model: ENV.fetch("OPENAI_EMBEDDING_MODEL", "text-embedding-3-small"),
        input: text
      }
      post_json("#{API_BASE}/embeddings", body).dig("data", 0, "embedding")
    end

    def summarize_document(text, language: "en")
      ensure_configured_or_mock!("OpenAI")
      return mock_document_summary(text, language) unless configured?

      body = {
        model: ENV.fetch("OPENAI_MODEL", "gpt-4o-mini"),
        messages: [{
          role: "user",
          content: <<~PROMPT
            Summarize workflows, tools, and friction points from this document for an enterprise discovery platform.
            Respond in #{language} as JSON: {"summary":"...","workflows":["..."],"friction_points":["..."],"tools_mentioned":["..."],"confidence":0.0}
            Document:
            #{text.truncate(12_000)}
          PROMPT
        }],
        response_format: { type: "json_object" }
      }
      content = post_json("#{API_BASE}/chat/completions", body).dig("choices", 0, "message", "content")
      normalize_document_insights(JSON.parse(content))
    rescue JSON::ParserError
      normalize_document_insights("summary" => content.to_s.truncate(500))
    end

    def understand_image_structured(file_path:, language: "en", caption: nil, department: nil)
      ensure_configured_or_mock!("OpenAI")
      return mock_image_structured(language, caption) unless configured?

      data = Base64.strict_encode64(File.binread(file_path))
      mime = mime_for_path(file_path)
      caption_line = caption.present? ? "Employee caption: #{caption}" : "Employee caption: (none)"
      body = {
        model: ENV.fetch("OPENAI_VISION_MODEL", "gpt-4o-mini"),
        messages: [{
          role: "user",
          content: [
            {
              type: "text",
              text: <<~PROMPT
                Analyze this work-related image for a workflow discovery interview.
                Department context: #{department.presence || "general"}.
                #{caption_line}
                Respond in #{language} as JSON only:
                {
                  "summary": "2-3 sentences describing what the image shows",
                  "tools_visible": ["tool or system names visible"],
                  "process_steps": ["observable process steps"],
                  "pain_points": ["workflow friction visible or implied"],
                  "confidence": 0.0
                }
                Set confidence between 0 and 1 based on image clarity and relevance.
              PROMPT
            },
            { type: "image_url", image_url: { url: "data:#{mime};base64,#{data}" } }
          ]
        }],
        response_format: { type: "json_object" },
        max_tokens: 700
      }
      content = post_json("#{API_BASE}/chat/completions", body).dig("choices", 0, "message", "content")
      normalize_image_insights(JSON.parse(content))
    rescue JSON::ParserError
      normalize_image_insights("summary" => content.to_s.truncate(500))
    end

    def understand_document_structured(text:, language: "en")
      ensure_configured_or_mock!("OpenAI")
      return mock_document_structured(text, language) unless configured?

      body = {
        model: ENV.fetch("OPENAI_MODEL", "gpt-4o-mini"),
        messages: [{
          role: "user",
          content: <<~PROMPT
            Extract workflow discovery insights from this document text.
            Respond in #{language} as JSON only:
            {
              "summary": "2-4 sentence overview",
              "workflows": ["concrete workflows described"],
              "friction_points": ["pain points or manual steps"],
              "tools_mentioned": ["systems or tools referenced"],
              "confidence": 0.0
            }
            Document:
            #{text.truncate(12_000)}
          PROMPT
        }],
        response_format: { type: "json_object" }
      }
      content = post_json("#{API_BASE}/chat/completions", body).dig("choices", 0, "message", "content")
      normalize_document_insights(JSON.parse(content))
    rescue JSON::ParserError
      normalize_document_insights("summary" => content.to_s.truncate(500))
    end

    def ocr_scanned_pdf(file_path:, language: "en")
      ensure_configured_or_mock!("OpenAI")
      return mock_scanned_pdf_text(language) unless configured?

      data = Base64.strict_encode64(File.binread(file_path))
      body = {
        model: ENV.fetch("OPENAI_VISION_MODEL", "gpt-4o-mini"),
        messages: [{
          role: "user",
          content: [
            {
              type: "text",
              text: "This PDF appears scanned or image-based. Extract all readable workflow-related text. Respond in #{language} with plain text only."
            },
            { type: "image_url", image_url: { url: "data:application/pdf;base64,#{data}" } }
          ]
        }],
        max_tokens: 1200
      }
      post_json("#{API_BASE}/chat/completions", body).dig("choices", 0, "message", "content").to_s.strip
    rescue StandardError => e
      raise unless MocksAllowed.allowed?

      Rails.logger.warn("[OCR] scanned_pdf fell back to mock: #{e.class}: #{e.message}")
      mock_scanned_pdf_text(language)
    end

    # Vision OCR for portal-uploaded PNG/JPG/WEBP (POD scans, screenshots, handwritten notes).
    def ocr_image(file_path:, language: "en")
      ensure_configured_or_mock!("OpenAI")
      return mock_image_ocr_text(language) unless configured?

      data = Base64.strict_encode64(File.binread(file_path))
      mime = mime_for_path(file_path)
      body = {
        model: ENV.fetch("OPENAI_VISION_MODEL", "gpt-4o-mini"),
        messages: [{
          role: "user",
          content: [
            {
              type: "text",
              text: <<~PROMPT
                Extract all readable text from this workplace image (screenshot, scanned form, or handwritten note).
                Include exception notes, labels, amounts, and any logistics or finance wording.
                If handwriting is present, transcribe it as best you can.
                Respond in #{language} with plain text only — no markdown fences.
              PROMPT
            },
            { type: "image_url", image_url: { url: "data:#{mime};base64,#{data}" } }
          ]
        }],
        max_tokens: 1200
      }
      post_json("#{API_BASE}/chat/completions", body).dig("choices", 0, "message", "content").to_s.strip
    rescue StandardError
      # Fall back to structured image understanding flattened to text
      begin
        structured = understand_image_structured(file_path: file_path, caption: nil, language: language)
        flatten_image_insights_to_text(structured)
      rescue StandardError => inner
        raise inner unless MocksAllowed.allowed?

        Rails.logger.warn("[OCR] image fell back to mock: #{inner.class}: #{inner.message}")
        mock_image_ocr_text(language)
      end
    end

    private

    def ensure_configured_or_mock!(service_name)
      return if configured?

      MocksAllowed.require!(service_name)
    end

    def api_key
      ENV["OPENAI_API_KEY"].presence
    end

    def post_json(url, body)
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5
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
      http.open_timeout = 5
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
      normalize_document_insights(
        "summary" => "Document describes operational workflows#{snippet.present? ? ": #{snippet}" : "."}",
        "workflows" => ["Documented process steps"],
        "friction_points" => ["Manual handoffs", "Spreadsheet dependency"],
        "tools_mentioned" => ["Excel"],
        "confidence" => 0.7
      )
    end

    def mock_image_structured(language, caption)
      summary = mock_image_description(language)
      normalize_image_insights(
        "summary" => summary,
        "tools_visible" => ["Excel"],
        "process_steps" => ["Manual invoice tracking"],
        "pain_points" => ["Manual data entry"],
        "confidence" => 0.75,
        "caption" => caption
      )
    end

    def mock_document_structured(text, language)
      mock_document_summary(text, language)
    end

    def mock_scanned_pdf_text(language)
      {
        "en" => "Scanned SOP checklist: manual invoice approval steps, Excel handoffs, and SAP re-entry every morning.",
        "es" => "Lista SOP escaneada: pasos manuales de aprobación de facturas, transferencias en Excel y reingreso en SAP."
      }.fetch(language, "Scanned document describing manual invoice approval and spreadsheet handoffs.")
    end

    def mock_image_ocr_text(language)
      {
        "en" => "POD exception note: damaged carton / short ship. AP retypes into Excel. Manual spreadsheet handoff before SAP.",
        "es" => "Nota de excepción POD: caja dañada / envío incompleto. AP reescribe en Excel."
      }.fetch(language, "Proof of delivery exception note with handwritten damage comment and Excel re-entry.")
    end

    def flatten_image_insights_to_text(structured)
      parts = [
        structured["summary"],
        Array(structured["process_steps"]).join(". "),
        Array(structured["pain_points"]).join(". "),
        Array(structured["tools_visible"]).join(", ")
      ]
      parts.map(&:presence).compact.join("\n").strip
    end

    def normalize_image_insights(payload)
      {
        "summary" => payload["summary"].to_s,
        "tools_visible" => Array(payload["tools_visible"]).map(&:to_s).reject(&:blank?),
        "process_steps" => Array(payload["process_steps"]).map(&:to_s).reject(&:blank?),
        "pain_points" => Array(payload["pain_points"]).map(&:to_s).reject(&:blank?),
        "confidence" => payload["confidence"].to_f.clamp(0.0, 1.0)
      }
    end

    def normalize_document_insights(payload)
      {
        "summary" => payload["summary"].to_s,
        "workflows" => Array(payload["workflows"]).map(&:to_s).reject(&:blank?),
        "friction_points" => Array(payload["friction_points"]).map(&:to_s).reject(&:blank?),
        "tools_mentioned" => Array(payload["tools_mentioned"]).map(&:to_s).reject(&:blank?),
        "confidence" => payload.fetch("confidence", 0.7).to_f.clamp(0.0, 1.0)
      }
    end
  end
end
