# frozen_string_literal: true

class PlatformAuditService
  def self.log!(platform_user:, action:, target: nil, metadata: {}, request: nil)
    PlatformAuditLog.create!(
      platform_user: platform_user,
      action: action,
      target_type: target&.class&.name,
      target_id: target&.id,
      metadata: metadata,
      ip_address: request&.remote_ip
    )
  end
end
