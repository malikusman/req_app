# frozen_string_literal: true

# Works out the Stage 1 quote once an engagement reaches pricing
# (Pricing::ProposeStage1). Enqueued after the hand-over commits, so it sees it.
class ProposeStage1Job < ApplicationJob
  queue_as :default

  def perform(engagement_id)
    engagement = Engagement.find_by(id: engagement_id)
    Pricing::ProposeStage1.call(engagement, reason: "Reached Stage 1 pricing") if engagement
  end
end
