# frozen_string_literal: true

# Explicit conversation track per message.
#
# Until now the discovery / companion / consultant-follow-up distinction rested on
# two booleans (`reviewer_followup`, `is_discovery_question`) plus a free-form
# `routing_decision` jsonb. Companion turns write `reviewer_followup: false`, so a
# companion message was indistinguishable from a discovery message at the column
# level — you had to parse `routing_decision["action"]` for "companion_*".
#
# `track` makes it a first-class fact, and `track_ref` points at the thing a turn
# belongs to (a consultant question, a requirement, a package) so an answer can be
# attributed back to what prompted it.
#
# `reviewer_followup` is deliberately left in place: the `discovery_only` scope, its
# supporting index, and the platform/company transcript views still read it. It is
# kept in step by a model callback and retired in a later pass.
class AddTrackToMessages < ActiveRecord::Migration[7.1]
  def up
    add_column :messages, :track, :string
    add_column :messages, :track_ref_type, :string
    add_column :messages, :track_ref_id, :bigint

    backfill_tracks!

    change_column_null :messages, :track, false

    add_index :messages, %i[conversation_id track created_at],
              name: "index_messages_on_conversation_track"
    add_index :messages, %i[track_ref_type track_ref_id],
              name: "index_messages_on_track_ref",
              where: "track_ref_type IS NOT NULL"
  end

  def down
    remove_index :messages, name: "index_messages_on_track_ref"
    remove_index :messages, name: "index_messages_on_conversation_track"
    remove_column :messages, :track_ref_id
    remove_column :messages, :track_ref_type
    remove_column :messages, :track
  end

  private

  # Deterministic, derived only from what is already stored. Order matters — the
  # first matching rule wins.
  #
  # Known imprecision: onboarding and profiling messages inside a conversation that
  # has since moved on are backfilled as "discovery", because nothing recorded the
  # conversation's status at the time. Only in-flight onboarding/profiling
  # conversations can be labelled accurately. Nothing keys off those two values, so
  # the historical blur is cosmetic — new messages are labelled at write time.
  def backfill_tracks!
    execute(<<~SQL.squish)
      UPDATE messages SET track = 'system'
       WHERE track IS NULL AND message_type = 'system'
    SQL

    execute(<<~SQL.squish)
      UPDATE messages SET track = 'consultant_followup'
       WHERE track IS NULL AND reviewer_followup = TRUE
    SQL

    execute(<<~SQL.squish)
      UPDATE messages SET track = 'companion'
       WHERE track IS NULL
         AND (agent_id = 'companion' OR routing_decision->>'action' LIKE 'companion%')
    SQL

    execute(<<~SQL.squish)
      UPDATE messages SET track = 'discovery'
       WHERE track IS NULL AND is_discovery_question = TRUE
    SQL

    # Still-in-flight conversations can be labelled from their current status.
    execute(<<~SQL.squish)
      UPDATE messages SET track = conversations.status
        FROM conversations
       WHERE messages.conversation_id = conversations.id
         AND messages.track IS NULL
         AND conversations.status IN ('onboarding', 'profiling')
    SQL

    execute(<<~SQL.squish)
      UPDATE messages SET track = 'discovery' WHERE track IS NULL
    SQL
  end
end
