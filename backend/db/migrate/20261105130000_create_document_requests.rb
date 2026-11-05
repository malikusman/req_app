# frozen_string_literal: true

# Documents asked for at the end of a conversation (Doc 06 §4.4, Doc 14 §11),
# and the uploads that answer them.
class CreateDocumentRequests < ActiveRecord::Migration[7.1]
  def change
    create_table :document_requests do |t|
      t.references :company, null: false, foreign_key: true
      t.references :conversation_session, null: false, foreign_key: true
      t.text :requested_item, null: false
      t.text :reason, null: false
      t.string :status, null: false, default: "REQUESTED"
      t.string :evidence, array: true, null: false, default: []
      t.datetime :reminded_at
      t.timestamps
    end

    add_reference :documents, :document_request, foreign_key: true, index: true
  end
end
