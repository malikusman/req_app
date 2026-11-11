# frozen_string_literal: true

# Who sees and decides Stage 1 prices on Mjadi's side (Doc 05 §10, Doc 17 §0.1,
# Decision Register J4). Every platform user can see the pricing queue, a
# quote's derivation and the rate card; only a super admin approves, adjusts,
# overrides the floor, rejects, or changes the rate card or the floor. The
# gate is permanent and not configurable.
class PricingPolicy < ApplicationPolicy
  APPROVER_ROLE = "super_admin"

  def show?
    platform?
  end

  def act?
    platform? && context.actor.respond_to?(:role) && context.actor.role == APPROVER_ROLE
  end
end
