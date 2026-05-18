# frozen_string_literal: true

class CreateReviewerFollowupTables < ActiveRecord::Migration[7.1]
  def change
    create_table :reviewer_info_requests do |t|
      t.references :company, null: false, foreign_key: true
      t.references :report, foreign_key: true
      t.references :reviewer_user, null: false, foreign_key: true
      t.references :employee, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.text :body, null: false
      t.string :status, default: "draft", null: false
      t.string :meta_message_id
      t.datetime :sent_at
      t.timestamps
    end

    add_index :reviewer_info_requests, %i[employee_id status],
              where: "status = 'awaiting_reply'",
              name: "index_reviewer_info_requests_awaiting_reply"

    create_table :reviewer_info_replies do |t|
      t.references :reviewer_info_request, null: false, foreign_key: true
      t.references :message, null: false, foreign_key: true
      t.text :body, null: false
      t.datetime :received_at, null: false
      t.timestamps
    end

    create_table :reviewer_chat_messages do |t|
      t.references :company, null: false, foreign_key: true
      t.references :sender_reviewer_user, null: false, foreign_key: { to_table: :reviewer_users }
      t.text :body, null: false
      t.timestamps
    end

    add_index :reviewer_chat_messages, %i[company_id created_at]
  end
end
