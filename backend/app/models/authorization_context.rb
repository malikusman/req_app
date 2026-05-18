# frozen_string_literal: true

AuthorizationContext = Struct.new(:actor, :audience, keyword_init: true) do
  def platform?
    audience == :platform
  end

  def company?
    audience == :company
  end

  def reviewer?
    audience == :reviewer
  end

  def assigned_company_ids
    return [] unless reviewer? && actor.respond_to?(:active_company_ids)

    actor.active_company_ids
  end

  def assigned_company?(company_id)
    assigned_company_ids.include?(company_id)
  end

  def company_id
    return actor.company_id if company?

    nil
  end
end
