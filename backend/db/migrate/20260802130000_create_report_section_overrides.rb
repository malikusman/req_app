# frozen_string_literal: true

class CreateReportSectionOverrides < ActiveRecord::Migration[7.1]
  def change
    create_table :report_section_overrides do |t|
      t.references :report, null: false, foreign_key: true
      t.references :reviewer_user, null: false, foreign_key: true
      t.string :action, null: false                 # hide | edit | add
      t.string :section_key                          # built-in key for hide/edit; slug for add
      t.string :anchor_section                       # for add: render after this section key
      t.string :title                                # for add / edit heading
      t.text :body                                   # for add / edit narrative
      t.integer :position, default: 0, null: false
      t.boolean :published, default: true, null: false
      t.timestamps
    end

    add_index :report_section_overrides, %i[report_id action]
    add_index :report_section_overrides, %i[report_id section_key]
  end
end
