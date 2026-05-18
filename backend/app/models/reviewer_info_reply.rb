# frozen_string_literal: true

class ReviewerInfoReply < ApplicationRecord
  belongs_to :reviewer_info_request
  belongs_to :message
end
