# frozen_string_literal: true

module Api
  module V1
    module Platform
      # The administrator's pricing queue and quote review (Doc 21 §26, Doc 17
      # §9). Every platform user can look; only a super admin acts
      # (PricingPolicy). The internal figures — hours, cost, margin, the rate
      # card — are shown here and nowhere a client can reach (Doc 17 §15).
      class Stage1QuotesController < BaseController
        before_action :set_quote, only: %i[show approve adjust change_inputs reject]
        before_action :authorize_act!, only: %i[approve adjust change_inputs reject calculate close]

        # The queue: proposed quotes first, or any status asked for.
        def index
          authorize :pricing, :show?
          statuses = Array(params[:status].presence || "PROPOSED") & Quote::STATUSES
          quotes = Quote.stage1.where(status: statuses).includes(:company, :engagement).order(created_at: :desc).limit(200)
          render json: { quotes: quotes.map { |q| summary_json(q) }, proposed_count: Quote.stage1.proposed.count }
        end

        def show
          authorize :pricing, :show?
          render json: detail_json(@quote)
        end

        def approve
          floor = params[:floor_override].present? ? params.require(:floor_override).permit(:reason, :free_text).to_h : nil
          render json: detail_json(review.approve(@quote, floor_override: floor))
        rescue Pricing::Review::Error => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        def adjust
          quote = review.adjust(@quote, subtotal: params[:subtotal], reason: params[:reason], free_text: params[:free_text])
          render json: detail_json(quote)
        rescue Pricing::Review::Error => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        def change_inputs
          quote = review.change_inputs(@quote, params.permit(*Pricing::Stage1Inputs::ADJUSTABLE).to_h)
          render json: detail_json(quote)
        rescue Pricing::Review::Error => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        def reject
          render json: detail_json(review.reject(@quote, note: params[:note]))
        rescue Pricing::Review::Error => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        # Works out the quote for an engagement now: one that reached pricing
        # before this existed, or a fresh one after a decline or an expiry.
        def calculate
          engagement = Engagement.find(params[:engagement_id])
          render json: detail_json(review.calculate(engagement)), status: :created
        rescue Pricing::Review::Error => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        # An engagement whose Stage 1 price wasn't agreed — after a decline, say —
        # closed by Mjadi with a reason. A quote still open is withdrawn.
        def close
          engagement = Engagement.find(params[:engagement_id])
          reason = params[:reason].to_s.strip
          return render json: { error: "Say why the engagement is being closed" }, status: :unprocessable_entity if reason.empty?

          engagement.with_lock do
            if (open = engagement.open_stage1_quote)
              open.update!(status: "SUPERSEDED")
              open.record!("superseded", actor: current_platform_user, detail: { reason: "Engagement closed" })
            end
            Engagements::Transition.call(engagement: engagement, to: "CLOSED", actor: current_platform_user,
                                         reason: reason, request: request)
          end
          render json: { engagement: { id: engagement.id, status: engagement.reload.status } }
        rescue Engagements::Transition::Error => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        private

        def set_quote
          @quote = Quote.stage1.find(params[:id])
        end

        def authorize_act!
          authorize :pricing, :act?
        end

        def review = Pricing::Review.new(actor: current_platform_user, request: request)

        def company_name(company) = company.display_name.presence || company.name

        def summary_json(quote)
          {
            id: quote.id, version: quote.version, status: quote.status, company_id: quote.company_id,
            company_name: company_name(quote.company), engagement_id: quote.engagement_id,
            total: quote.total.to_s("F"), subtotal: quote.subtotal.to_s("F"), currency: quote.currency,
            participants_included: quote.participants_included, deep_dives_included: quote.deep_dives_included,
            margin_percent: quote.margin_percent.to_s("F"), below_floor: quote.below_floor,
            confidence: quote.estimate["confidence"], created_at: quote.created_at, issued_at: quote.issued_at,
            valid_until: quote.valid_until
          }
        end

        def detail_json(quote)
          engagement = quote.engagement
          {
            quote: summary_json(quote).merge(
              line_items: quote.line_items, tax_rate: quote.tax_rate.to_s("F"), tax_amount: quote.tax_amount.to_s("F"),
              additional_participant_rate: quote.additional_participant_rate.to_s("F"),
              inputs: quote.inputs, estimate: quote.estimate, internal: quote.internal,
              admin_explanation: quote.admin_explanation, client_scope: quote.client_scope,
              explanation_source: quote.explanation_source,
              approved_by: quote.approved_by&.name, approved_at: quote.approved_at,
              accepted_by: quote.accepted_by&.name, accepted_at: quote.accepted_at,
              declined_at: quote.declined_at, decline_reason: quote.decline_reason,
              rejected_by: quote.rejected_by&.name, rejected_at: quote.rejected_at, rejection_note: quote.rejection_note,
              first_viewed_at: quote.first_viewed_at, pdf_ready: quote.pdf_storage_key.present?
            ),
            engagement: { id: engagement.id, status: engagement.status, languages: engagement.languages,
                          planned_departments: engagement.planned_departments,
                          lead_consultant: engagement.lead_consultant&.name },
            comparables: Pricing::Comparables.for(engagement, quote.participants_included),
            rate_card: { version: quote.rate_card_version.version, placeholder: quote.rate_card_version.placeholder },
            margin_floor: { version: quote.margin_floor_version.version,
                            percent: quote.margin_floor_version.percent.to_s("F") },
            overrides: quote.estimate_overrides.order(:created_at).map do |o|
              o.slice(:kind, :structured_reason, :free_text, :created_at)
               .merge(original_total: o.original_total.to_s("F"), adjusted_total: o.adjusted_total.to_s("F"),
                      actor: o.actor.name)
            end,
            events: quote.events.map { |e| { event: e.event, at: e.created_at, by: e.actor.try(:name), detail: e.detail } },
            versions: engagement.quotes.stage1.order(version: :desc).map { |q| summary_json(q) },
            override_reasons: EstimateOverride::REASONS,
            can_act: policy(:pricing).act?
          }
        end
      end
    end
  end
end
