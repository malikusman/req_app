# frozen_string_literal: true

class ApplicationPolicy
  attr_reader :context, :record

  def initialize(context, record)
    @context = context
    @record = record
  end

  def index?
    false
  end

  def show?
    false
  end

  def create?
    false
  end

  def update?
    false
  end

  def destroy?
    false
  end

  class Scope
    attr_reader :context, :scope

    def initialize(context, scope)
      @context = context
      @scope = scope
    end

    def resolve
      scope.none
    end

    private

    def platform?
      context.platform?
    end

    def company?
      context.company?
    end

    def reviewer?
      context.reviewer?
    end

    def company_id
      context.company_id
    end

    def assigned_company_ids
      context.assigned_company_ids
    end
  end

  private

  def platform?
    context.platform?
  end

  def company?
    context.company?
  end

  def reviewer?
    context.reviewer?
  end

  def company_id
    context.company_id
  end

  def assigned_company_ids
    context.assigned_company_ids
  end

  def assigned_company?(id)
    context.assigned_company?(id)
  end

  def same_company?(record)
    company? && record.respond_to?(:company_id) && record.company_id == company_id
  end

  def company_admin?
    company? && context.actor.respond_to?(:company_admin?) && context.actor.company_admin?
  end
end
