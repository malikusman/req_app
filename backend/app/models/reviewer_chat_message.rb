# frozen_string_literal: true

class ReviewerChatMessage < ApplicationRecord
  belongs_to :company
  belongs_to :sender_reviewer_user, class_name: "ReviewerUser"
end
