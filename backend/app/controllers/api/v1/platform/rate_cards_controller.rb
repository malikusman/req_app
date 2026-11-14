# frozen_string_literal: true

module Api
  module V1
    module Platform
      # The Stage 1 rate card and the margin floor (Doc 17 §7–8, Doc 21 §27):
      # the values in effect, every earlier version with who changed it and why,
      # and — for a super admin — a new version of either. INTERNAL_COMMERCIAL:
      # platform users only.
      class RateCardsController < BaseController
        def show
          authorize :pricing, :show?
          render json: payload
        end

        def create
          authorize :pricing, :act?
          Pricing::NewVersions.new(actor: current_platform_user, request: request).rate_card(rate_card_params)
          render json: payload, status: :created
        rescue Pricing::NewVersions::Error => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        def create_floor
          authorize :pricing, :act?
          Pricing::NewVersions.new(actor: current_platform_user, request: request)
                              .margin_floor(percent: params[:percent], reason: params[:reason])
          render json: payload, status: :created
        rescue Pricing::NewVersions::Error => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        private

        def rate_card_params
          params.permit(:currency, :placeholder, :reason, :consultant_internal_cost, :consultant_charge_rate,
                        stage1: {}).to_h
        end

        def payload
          rate_card = RateCardVersion.current
          floor = MarginFloorVersion.current
          {
            rate_card: rate_card && rate_card_json(rate_card),
            rate_cards: RateCardVersion.order(version: :desc).map { |r| version_json(r) },
            margin_floor: floor && floor_json(floor),
            margin_floors: MarginFloorVersion.order(version: :desc).map { |f| floor_json(f) },
            # Quotes still with the administrator made on an earlier rate card.
            waiting_on_older_rates: rate_card ? Quote.stage1.proposed.where.not(rate_card_version_id: rate_card.id).count : 0,
            can_act: policy(:pricing).act?
          }
        end

        def rate_card_json(record)
          version_json(record).merge(
            stage1: record.stage1,
            consultant_internal_cost: record.rates.dig("consultant", "mjadi_team", "internal_cost"),
            consultant_charge_rate: record.rates.dig("consultant", "mjadi_team", "charge_rate")
          )
        end

        def version_json(record)
          { version: record.version, effective_from: record.effective_from, currency: record.currency,
            placeholder: record.placeholder, reason: record.reason, changed_by: record.changed_by.try(:name),
            quotes: Quote.where(rate_card_version_id: record.id).count }
        end

        def floor_json(record)
          { version: record.version, percent: record.percent.to_s("F"), effective_from: record.effective_from,
            reason: record.reason, changed_by: record.changed_by.try(:name) }
        end
      end
    end
  end
end
