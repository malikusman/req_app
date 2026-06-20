# frozen_string_literal: true

module Multimodal
  # Structured extraction for WhatsApp voice, image, and document attachments.
  class UnderstandingService
    Result = Struct.new(:plain_text, :structured_insights, :confidence, keyword_init: true)

    def self.call(attachment:, file_path:)
      new(attachment: attachment, file_path: file_path).call
    end

    def initialize(attachment:, file_path:)
      @attachment = attachment
      @file_path = file_path
      @employee = attachment.employee
      @company = attachment.company
      @openai = Openai::Client.new
    end

    def call
      lang = @employee.preferred_language.presence || @company.locale

      case @attachment.attachment_type
      when "audio"
        understand_audio(lang)
      when "image"
        understand_image(lang)
      when "document"
        understand_document(lang)
      else
        Result.new(plain_text: "", structured_insights: {}, confidence: nil)
      end
    end

    private

    def understand_audio(lang)
      text = @openai.transcribe_audio(file_path: @file_path, language: lang)
      structured = { "text" => text, "media_type" => "audio" }
      Result.new(plain_text: text, structured_insights: structured, confidence: text.present? ? 0.85 : nil)
    end

    def understand_image(lang)
      structured = @openai.understand_image_structured(
        file_path: @file_path,
        language: lang,
        caption: @attachment.caption,
        department: @employee.department
      )
      Result.new(
        plain_text: structured["summary"].to_s,
        structured_insights: structured.merge("media_type" => "image"),
        confidence: structured["confidence"]
      )
    end

    def understand_document(lang)
      raw = DocumentTextExtractor.extract(file_path: @file_path, content_type: @attachment.mime_type)
      structured = if raw.present?
                     @openai.understand_document_structured(text: raw, language: lang)
                   else
                     @openai.understand_image_structured(
                       file_path: @file_path,
                       language: lang,
                       caption: @attachment.caption,
                       department: @employee.department
                     )
                   end
      structured = structured.merge("media_type" => "document", "raw_excerpt" => raw.to_s.truncate(2000))
      plain = [structured["summary"], *Array(structured["workflows"]), *Array(structured["friction_points"])].compact.join("\n")
      Result.new(
        plain_text: plain.presence || structured["summary"].to_s,
        structured_insights: structured,
        confidence: structured["confidence"]
      )
    end
  end
end
