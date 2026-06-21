# frozen_string_literal: true

class AddMultimodalConsentTextVersion < ActiveRecord::Migration[7.1]
  def up
    ConsentTextVersion.where(active: true).update_all(active: false)

    %w[en es].each do |locale|
      body = locale == "en" ? en_consent : es_consent
      keywords = locale == "en" ? %w[YES I\ AGREE] : %w[SI YES]

      ConsentTextVersion.find_or_create_by!(version: "2026-06-20", locale: locale) do |record|
        record.body = body
        record.confirmation_keywords = keywords
        record.active = true
      end.update!(body: body, confirmation_keywords: keywords, active: true)
    end
  end

  def down
    ConsentTextVersion.where(version: "2026-06-20").delete_all
    ConsentTextVersion.where(version: "2026-05-01").update_all(active: true)
  end

  private

  def en_consent
    <<~TEXT.squish
      Before we begin: we'll ask about 10 questions about your daily workflows via WhatsApp.
      You can reply with text, voice notes, screenshots, or PDFs if that's easier.
      Optional media may be transcribed or analyzed by AI to understand your work; only summarized
      insights are shared with authorized leads—not raw chat logs or original files.
      Reply YES to continue or STOP to opt out.
    TEXT
  end

  def es_consent
    <<~TEXT.squish
      Antes de comenzar: te haremos unas 10 preguntas sobre tus flujos de trabajo por WhatsApp.
      Puedes responder con texto, notas de voz, capturas o PDFs si te resulta más fácil.
      Los medios opcionales pueden transcribirse o analizarse con IA; los responsables autorizados
      ven resúmenes, no el chat completo ni los archivos originales. Responde SI para continuar o STOP para cancelar.
    TEXT
  end
end
