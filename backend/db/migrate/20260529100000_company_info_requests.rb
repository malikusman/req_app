# frozen_string_literal: true

class CompanyInfoRequests < ActiveRecord::Migration[7.1]
  def change
    create_table :company_info_requests do |t|
      t.references :company, null: false, foreign_key: true
      t.string :requested_by_type, null: false
      t.bigint :requested_by_id, null: false
      t.string :profile_section
      t.string :subject, null: false
      t.text :body, null: false
      t.string :status, null: false, default: "open"
      t.datetime :due_at
      t.datetime :closed_at
      t.timestamps
    end

    add_index :company_info_requests, %i[requested_by_type requested_by_id], name: "index_company_info_requests_on_requested_by"
    add_index :company_info_requests, %i[company_id status]

    create_table :company_info_request_replies do |t|
      t.references :company_info_request, null: false, foreign_key: true
      t.string :sender_type, null: false
      t.bigint :sender_id, null: false
      t.text :body, null: false
      t.references :document, foreign_key: true
      t.timestamps
    end

    add_index :company_info_request_replies, %i[sender_type sender_id], name: "index_company_info_replies_on_sender"
  end
end
