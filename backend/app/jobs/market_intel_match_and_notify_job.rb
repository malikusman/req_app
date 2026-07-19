# frozen_string_literal: true

class MarketIntelMatchAndNotifyJob < ApplicationJob
  queue_as :default

  def perform
    MarketIntel::MatchAndNotifyService.call
  end
end
