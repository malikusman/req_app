# frozen_string_literal: true

module Api
  module V1
    module Company
      # The client's Stage 1 proposal (Doc 17 §10, Doc 21 §10). Anyone at the
      # company can read it once an administrator has issued it; the key user
      # accepts or declines (Doc 21 §44). Only the client view is ever sent —
      # never the cost basis, hours or margin (Doc 17 §15).
      class Stage1QuotesController < BaseController
        before_action :set_quote, except: :show
        before_action :refuse_impersonation, only: %i[accept decline]

        rescue_from Pricing::ClientDecision::Error do |e|
          render json: { error: e.message }, status: e.status
        end

        # The proposal to show now, or null while one is being prepared.
        def show
          quote = Pricing::ClientQuoteView.current_for(current_company.current_engagement)
          return render json: { quote: nil } unless quote

          note_first_view(quote)
          render json: { quote: Pricing::ClientQuoteView.new(quote, viewer: current_company_user).json }
        end

        def pdf
          body, type = Pricing::QuotePdf.fetch(@quote)
          extension = type == "application/pdf" ? "pdf" : "html"
          send_data body, type: type, disposition: "attachment",
                          filename: "Mjadi-Stage-1-proposal-v#{@quote.version}.#{extension}"
        end

        def accept
          acknowledged = ActiveModel::Type::Boolean.new.cast(params[:acknowledged])
          quote = Pricing::ClientDecision.new(@quote, current_company_user).accept(acknowledged: acknowledged)
          render json: { quote: Pricing::ClientQuoteView.new(quote, viewer: current_company_user).json }
        end

        def decline
          quote = Pricing::ClientDecision.new(@quote, current_company_user).decline(reason: params[:reason])
          render json: { quote: Pricing::ClientQuoteView.new(quote, viewer: current_company_user).json }
        end

        private

        def set_quote
          @quote = Pricing::ClientQuoteView.current_for(current_company.current_engagement)
          raise ActiveRecord::RecordNotFound unless @quote && @quote.id == params[:id].to_i
        end

        # Doc 17 §18: when the client first opened it.
        def note_first_view(quote)
          return unless quote.issued? && quote.first_viewed_at.nil? && !impersonating?

          quote.update!(first_viewed_at: Time.current)
          quote.record!("viewed", actor: current_company_user)
        end

        # The client agrees the price, not Mjadi acting as them.
        def refuse_impersonation
          return unless impersonating?

          render json: { error: "Only the client can accept or decline the proposal" }, status: :forbidden
        end
      end
    end
  end
end
