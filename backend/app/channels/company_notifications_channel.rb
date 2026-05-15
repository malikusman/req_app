# frozen_string_literal: true

class CompanyNotificationsChannel < ApplicationCable::Channel
  def subscribed
    stream_for current_company_user
  end

  def unsubscribed
    stop_all_streams
  end
end
