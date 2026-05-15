# frozen_string_literal: true

class LanguageDetector
  # ISO 639-1 codes
  PATTERNS = {
    "es" => /\b(hola|gracias|sí|si|buenos|estoy|también|porque|trabajo)\b/i,
    "fr" => /\b(bonjour|merci|oui|je|nous|travail|bonsoir)\b/i,
    "de" => /\b(hallo|danke|ich|wir|arbeit|guten)\b/i,
    "pt" => /\b(olá|obrigado|sim|trabalho|bom dia)\b/i
  }.freeze

  def self.detect(text)
    return "en" if text.blank?

    PATTERNS.each do |code, pattern|
      return code if text.match?(pattern)
    end

    "en"
  end
end
