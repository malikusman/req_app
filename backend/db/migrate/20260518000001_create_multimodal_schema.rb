# frozen_string_literal: true

class CreateMultimodalSchema < ActiveRecord::Migration[7.1]
  def change
    create_table :documents do |t|
      t.references :company, null: false, foreign_key: true
      t.references :employee, foreign_key: true
      t.references :conversation, foreign_key: true
      t.references :message, foreign_key: true
      t.references :uploaded_by_company_user, foreign_key: { to_table: :company_users }
      t.string :source, null: false, default: "company_portal_upload"
      t.string :department
      t.string :filename, null: false
      t.string :content_type
      t.bigint :byte_size, default: 0, null: false
      t.string :storage_key, null: false
      t.string :status, default: "pending", null: false
      t.text :processing_error
      t.jsonb :insights_preview, default: {}, null: false
      t.jsonb :metadata, default: {}, null: false
      t.timestamps
    end
    add_index :documents, [:company_id, :status]

    create_table :media_attachments do |t|
      t.references :message, null: false, foreign_key: true
      t.references :company, null: false, foreign_key: true
      t.references :employee, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.string :attachment_type, null: false
      t.string :mime_type
      t.string :storage_key
      t.string :meta_media_id
      t.string :status, default: "pending", null: false
      t.text :extracted_text
      t.text :processing_error
      t.jsonb :metadata, default: {}, null: false
      t.timestamps
    end
    add_index :media_attachments, :meta_media_id, unique: true, where: "meta_media_id IS NOT NULL"

    create_table :document_chunks do |t|
      t.references :document, null: false, foreign_key: true
      t.integer :chunk_index, null: false
      t.text :content, null: false
      t.vector :embedding, limit: 1536
      t.jsonb :metadata, default: {}, null: false
      t.timestamps
    end
    add_index :document_chunks, [:document_id, :chunk_index], unique: true
  end
end
