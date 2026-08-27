# frozen_string_literal: true

class ConsultantInfoReply < ApplicationRecord
  belongs_to :consultant_info_request
  belongs_to :message
end
