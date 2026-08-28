# frozen_string_literal: true

# What a consultant needs to know, as its own object.
#
# The consultant does not write question text. They state the information they need
# in their own words, and the agent drafts questions from that. One stated need can
# produce several questions, and the agent has to know when the need is *met* —
# which a bare list of questions cannot express. Hence a first-class requirement,
# separate from the questions generated for it.
class CreateConsultantRequirements < ActiveRecord::Migration[7.1]
  def change
    create_table :consultant_requirements do |t|
      t.references :consultant_user, null: false, foreign_key: true
      t.references :discovery_package, null: false, foreign_key: true
      t.references :employee, null: false, foreign_key: true
      t.references :company, null: false, foreign_key: true

      # Their own words. Drafted from, never sent to the employee verbatim.
      t.text :statement, null: false
      t.string :status, null: false, default: "open"

      # Per-requirement budget. Defaults resolve company -> ENV -> code default in
      # Discovery::FollowupLimits; stored per row so a raised budget survives.
      t.integer :max_questions, null: false, default: 3

      # agent_judged | consultant_manual — both paths exist, and the consultant
      # always wins.
      t.string :satisfaction_basis
      t.datetime :satisfied_at
      # What the agent thinks is still unanswered. Drives the next draft and shows
      # the consultant why the requirement is still open.
      t.jsonb :missing_aspects, null: false, default: []

      t.timestamps
    end

    add_index :consultant_requirements, %i[discovery_package_id status]
    add_index :consultant_requirements, %i[employee_id status]

    # Now that the requirements table exists, the questions can point at it. Left
    # out of the package migration deliberately: a column referencing a table that
    # does not exist yet is worse than adding it alongside its target.
    add_reference :discovery_followup_questions, :consultant_requirement,
                  foreign_key: true, index: true

    # Delivery reuses the existing consultant -> employee ask channel rather than
    # introducing a third one. The link is what lets an inbound reply find the
    # question it answers, and through it the requirement to re-evaluate.
    add_reference :discovery_followup_questions, :consultant_info_request,
                  foreign_key: true, index: true
  end
end
