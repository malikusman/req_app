# frozen_string_literal: true

class EnrichMediaAttachments < ActiveRecord::Migration[7.1]
  def change
    change_table :media_attachments, bulk: true do |t|
      t.text :caption
      t.jsonb :structured_insights, null: false, default: {}
      t.float :confidence
      t.integer :duration_ms
      t.string :language
      t.references :document, foreign_key: true
    end
  end
end
