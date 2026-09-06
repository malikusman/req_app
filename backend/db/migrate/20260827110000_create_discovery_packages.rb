# frozen_string_literal: true

# The structured handover from Discovery to the consultant.
#
# On completion the interview used to leave behind a transcript and a blackboard. A
# consultant then had to read the conversation to work out what it meant. The
# package makes the handover explicit: a recommendation, the issues found, possible
# solutions, and the questions the agent intends to ask next.
#
# Three tables rather than one jsonb column, because the consultant amends
# individual issues and solutions, and follow-up questions carry real lifecycle
# state plus foreign keys to messages. A single blob would force read-modify-write
# over the whole package on every edit and give up referential integrity on the
# question -> message link.
class CreateDiscoveryPackages < ActiveRecord::Migration[7.1]
  def change
    create_table :discovery_packages do |t|
      # The package belongs to the interview, not to a report — a report may not
      # exist yet, and often won't when the consultant first reads this.
      t.references :conversation, null: false, foreign_key: true
      t.references :employee, null: false, foreign_key: true
      t.references :company, null: false, foreign_key: true

      # Increments on an addendum reopen; the previous version is superseded.
      t.integer :version, null: false, default: 1
      t.string :status, null: false, default: "generating"

      t.text :recommendation
      # Separate so a consultant can rewrite the call without the reasoning, or
      # the reasoning without the call.
      t.text :recommendation_rationale
      t.float :confidence

      # Verbatim agent output, kept immutable for audit after the consultant edits.
      # Never read for display.
      t.jsonb :agent_payload, null: false, default: {}
      # "llm" or "deterministic" — mirrors Reports::NarrativeWriter#generated_by, so
      # a package built without a model is honest about it.
      t.string :generated_by
      t.text :error_message

      t.datetime :generated_at
      t.timestamps
    end

    add_index :discovery_packages, %i[conversation_id version], unique: true
    add_index :discovery_packages, %i[company_id status]

    create_table :discovery_package_items do |t|
      t.references :discovery_package, null: false, foreign_key: true
      # One table for both: the consultant's accept/amend/reject lifecycle is
      # identical for an issue and for a solution.
      t.string :kind, null: false
      t.string :title
      t.text :body
      # A band, not a float. The report layer already learned that lesson.
      t.string :impact
      t.jsonb :evidence_refs, null: false, default: []
      t.string :origin, null: false, default: "agent"
      t.string :status, null: false, default: "proposed"
      # Ties a solution to the issue it addresses.
      t.bigint :linked_item_id
      t.integer :ordinal, null: false, default: 0
      t.timestamps
    end

    add_index :discovery_package_items, %i[discovery_package_id kind ordinal],
              name: "index_package_items_on_package_kind_ordinal"
    add_index :discovery_package_items, :linked_item_id, where: "linked_item_id IS NOT NULL"
    add_foreign_key :discovery_package_items, :discovery_package_items, column: :linked_item_id

    create_table :discovery_followup_questions do |t|
      t.references :discovery_package, null: false, foreign_key: true
      # Authored by the agent. A consultant states what they need to know and the
      # agent drafts from that — they never type question text.
      t.text :body, null: false
      # Why it's being asked. Shown to the consultant, not to the employee.
      t.text :rationale
      t.string :status, null: false, default: "drafted"
      # Position 1 is "the next one queued".
      t.integer :queue_position, null: false, default: 0

      t.references :sent_message, foreign_key: { to_table: :messages }
      t.references :answered_message, foreign_key: { to_table: :messages }

      # Which parked aside from the interview produced this question.
      t.jsonb :source_parked_ref, null: false, default: {}
      t.datetime :sent_at
      t.datetime :answered_at
      t.timestamps
    end

    add_index :discovery_followup_questions, %i[discovery_package_id queue_position],
              name: "index_followup_questions_on_package_position"
    add_index :discovery_followup_questions, :status

    # consultant_requirement_id is deliberately NOT added here. The requirements
    # table arrives with the consultant review work, and a column pointing at a
    # table that does not exist yet is worse than adding it alongside its target.
  end
end
