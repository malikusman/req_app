# frozen_string_literal: true

class PhoneNormalizer
  def self.call(phone)
    cleaned = phone.to_s.gsub(/[\s\-\(\)]/, "")
    cleaned = "+#{cleaned}" unless cleaned.start_with?("+")
    cleaned
  end
end
