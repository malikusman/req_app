# frozen_string_literal: true

class ReportShareAccess < ApplicationRecord
  belongs_to :report

  validates :share_token, :accessed_at, presence: true
end
