# frozen_string_literal: true

# Expires issued quotes past their validity date (Pricing::Expire). Daily.
class ExpireQuotesJob < ApplicationJob
  queue_as :default

  def perform
    Pricing::Expire.call
  end
end
