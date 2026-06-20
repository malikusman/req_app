# frozen_string_literal: true

module Multimodal
  class FailureNotifier
    MESSAGES = {
      "en" => "Sorry, I couldn't process that %{type}. Please try sending a clearer version or type a short summary in text.",
      "es" => "No pude procesar ese %{type}. Intenta enviar una versión más clara o escribe un resumen breve.",
      "fr" => "Désolé, je n'ai pas pu traiter ce %{type}. Merci d'envoyer une version plus claire ou un résumé texte.",
      "de" => "Entschuldigung, das %{type} konnte ich nicht verarbeiten. Bitte senden Sie eine klarere Version oder eine kurze Textzusammenfassung."
    }.freeze

    TYPE_LABELS = {
      "audio" => { "en" => "voice note", "es" => "nota de voz", "fr" => "message vocal", "de" => "Sprachnachricht" },
      "image" => { "en" => "image", "es" => "imagen", "fr" => "image", "de" => "Bild" },
      "document" => { "en" => "document", "es" => "documento", "fr" => "document", "de" => "Dokument" }
    }.freeze

    def self.call(attachment:)
      new(attachment: attachment).call
    end

    def initialize(attachment:)
      @attachment = attachment
      @employee = attachment.employee
      @conversation = attachment.conversation
      @company = attachment.company
    end

    def call
      lang = @employee.preferred_language.presence || @company.locale
      type_label = TYPE_LABELS.fetch(@attachment.attachment_type, TYPE_LABELS["document"])
                                .fetch(lang, TYPE_LABELS[@attachment.attachment_type]["en"])
      template = MESSAGES.fetch(lang, MESSAGES["en"])
      body = format(template, type: type_label)

      @conversation.messages.create!(
        direction: "outbound",
        message_type: "text",
        body: body
      )

      client = Whatsapp::MetaClient.new
      if client.configured?
        client.send_text(to: @employee.phone_e164, body: body)
      else
        Rails.logger.info("[Multimodal failure] to=#{@employee.phone_e164} body=#{body}")
      end
    end
  end
end
