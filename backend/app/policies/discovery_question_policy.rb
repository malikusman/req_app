# frozen_string_literal: true

class DiscoveryQuestionPolicy < ApplicationPolicy
  def index?
    company?
  end

  def feedback?
    company?
  end
end
