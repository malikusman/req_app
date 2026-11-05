# frozen_string_literal: true

# One model call: which prompt version, which model, how long it took, what it
# cost in tokens and whether it worked (Doc 05 §21 "AI run", Doc 08 §30). A
# fallback says why, so "nothing found" is never confused with "it failed"
# (Doc 05 §3.5). Written by the steps that call the model, not by Openai::Client.
class AiRun < ApplicationRecord
  belongs_to :company
  belongs_to :engagement, optional: true
  belongs_to :subject, polymorphic: true, optional: true

  # P02 interviewer, P03 turn capture, P04 findings and context.
  STAGES = %w[P02 P03 P04].freeze
  # RETRIED: worked on a second attempt. FALLBACK: the platform used its own
  # safe output instead. FAILED: nothing usable, and no fallback applies.
  STATUSES = %w[OK RETRIED FALLBACK FAILED].freeze

  validates :stage, inclusion: { in: STAGES }
  validates :status, inclusion: { in: STATUSES }
end
