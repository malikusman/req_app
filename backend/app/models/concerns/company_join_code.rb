# frozen_string_literal: true

module CompanyJoinCode
  extend ActiveSupport::Concern

  JOIN_CODE_FORMAT = /\A[A-Z0-9]{5}\z/

  included do
    validates :join_code, presence: true, uniqueness: true, format: { with: JOIN_CODE_FORMAT }, on: :update
    before_validation :assign_join_code, on: :create
  end

  class_methods do
    def generate_join_code
      loop do
        code = SecureRandom.alphanumeric(5).upcase
        break code unless exists?(join_code: code)
      end
    end

    def find_by_join_code(plain)
      normalized = normalize_join_code(plain)
      return nil if normalized.blank?

      find_by(join_code: normalized)
    end

    def normalize_join_code(plain)
      plain.to_s.gsub(/\s+/, "").upcase.presence
    end
  end

  def ensure_join_code!
    return join_code if join_code.present?

    update!(join_code: self.class.generate_join_code)
    join_code
  end

  def rotate_join_code!
    update!(join_code: self.class.generate_join_code, pin_rotated_at: Time.current)
    join_code
  end

  def verify_join_code?(plain)
    normalized = self.class.normalize_join_code(plain)
    normalized.present? && join_code == normalized
  end

  private

  def assign_join_code
    self.join_code ||= self.class.generate_join_code
  end
end
