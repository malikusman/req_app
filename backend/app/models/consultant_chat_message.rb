# frozen_string_literal: true

class ConsultantChatMessage < ApplicationRecord
  belongs_to :company
  belongs_to :sender_consultant_user, class_name: "ConsultantUser"
end
