# frozen_string_literal: true

class AddReviewerFollowupToMessages < ActiveRecord::Migration[7.1]
  def change
    add_column :messages, :reviewer_followup, :boolean, default: false, null: false
    add_index :messages, %i[conversation_id reviewer_followup created_at],
              name: "index_messages_on_conversation_followup"
  end
end
