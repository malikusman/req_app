# frozen_string_literal: true

# Email delivery, and a tokenised web reply, for consultant follow-up questions.
#
# The email-plus-reply-link flow already existed on ConsultantOutreach. Follow-up
# questions go out on ConsultantInfoRequest instead, and routing them through
# Outreach is not an option today: Outreaches::CreateService always sets
# `pending_admin_approval`, so every consultant question would need a company admin
# to approve it before the employee ever saw it.
#
# So rather than move the questions or duplicate the token logic, the token machinery
# becomes shared (TokenisedReply, included by both records) and one public endpoint
# resolves either kind. That is a step toward consolidating the two channels rather
# than another thing to merge later.
class AddEmailDeliveryToConsultantInfoRequests < ActiveRecord::Migration[7.1]
  def change
    add_column :consultant_info_requests, :channel, :string, null: false, default: "whatsapp"
    add_column :consultant_info_requests, :reply_token_digest, :string
    add_column :consultant_info_requests, :email_sent_at, :datetime

    add_index :consultant_info_requests, :reply_token_digest,
              unique: true, where: "reply_token_digest IS NOT NULL"
  end
end
