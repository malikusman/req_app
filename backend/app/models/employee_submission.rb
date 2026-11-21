class EmployeeSubmission < ApplicationRecord
  belongs_to :conversation
  has_one :message
  validates :submission_id, presence: true, length: { maximum: 100 }
end
