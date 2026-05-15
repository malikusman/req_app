# frozen_string_literal: true

class DiscoveryPlaybook < ApplicationRecord
  belongs_to :created_by_platform_user, class_name: "PlatformUser", optional: true

  validates :department, :version, :prompt_block, presence: true

  scope :active_for, ->(department) { where(department: department, active: true) }

  def self.active_playbook_for(department)
    active_for(department).first || active_for("default").first
  end
end
