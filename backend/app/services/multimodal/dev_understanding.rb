# frozen_string_literal: true

module Multimodal
  # Deterministic structured extraction for dev/simulator media processing.
  module DevUnderstanding
    module_function

    def call(attachment:, language: "en")
      case attachment.attachment_type
      when "audio"
        audio_result(language)
      when "image"
        image_result(language, attachment.caption)
      when "document"
        document_result(language, attachment.caption)
      else
        UnderstandingService::Result.new(plain_text: "", structured_insights: {}, confidence: nil)
      end
    end

    def audio_result(language)
      text = {
        "en" => "I spend mornings reconciling invoices in Excel before uploading to SAP.",
        "es" => "Paso las mañanas conciliando facturas en Excel antes de subirlas a SAP."
      }.fetch(language, "Voice note about manual invoice reconciliation in Excel and SAP.")
      UnderstandingService::Result.new(
        plain_text: text,
        structured_insights: { "text" => text, "media_type" => "audio" },
        confidence: 0.85
      )
    end

    def image_result(language, caption)
      summary = {
        "en" => "SAP invoice entry screen with manual spreadsheet columns visible.",
        "es" => "Pantalla de entrada de facturas SAP con columnas de hoja de cálculo manual."
      }.fetch(language, "Work-related screenshot showing SAP invoice workflow.")
      UnderstandingService::Result.new(
        plain_text: summary,
        structured_insights: {
          "summary" => summary,
          "tools_visible" => ["SAP", "Excel"],
          "process_steps" => ["Manual invoice entry"],
          "pain_points" => ["Manual data entry", "Spreadsheet re-entry"],
          "media_type" => "image",
          "caption" => caption
        },
        confidence: 0.82
      )
    end

    def document_result(language, caption)
      summary = {
        "en" => "Month-end close checklist with manual Excel handoffs and SAP re-entry steps.",
        "es" => "Lista de cierre de mes con transferencias manuales en Excel y pasos de reingreso en SAP."
      }.fetch(language, "Document describing manual close checklist and spreadsheet handoffs.")
      UnderstandingService::Result.new(
        plain_text: summary,
        structured_insights: {
          "summary" => summary,
          "workflows" => ["Month-end close checklist"],
          "friction_points" => ["Manual Excel handoffs", "SAP re-entry"],
          "tools_mentioned" => ["Excel", "SAP"],
          "media_type" => "document",
          "caption" => caption
        },
        confidence: 0.78
      )
    end
  end
end
