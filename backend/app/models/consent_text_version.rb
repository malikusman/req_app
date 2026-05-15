# frozen_string_literal: true

class ConsentTextVersion < ApplicationRecord
  scope :active_for, ->(locale) { where(locale: locale, active: true) }

  validates :version, :body, presence: true
end
