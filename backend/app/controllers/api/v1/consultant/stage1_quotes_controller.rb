# frozen_string_literal: true

module Api
  module V1
    module Consultant
      # Where the Stage 1 proposal stands, for the consultants assigned to the
      # company (Doc 21 §44: consultants view quotes). They see what the client
      # sees and the newest version's status — never the cost basis, hours or
      # margin (Doc 17 §15: only where administrator policy permits; it doesn't).
      class Stage1QuotesController < BaseController
        def show
          company = ::Company.find(params[:company_id])
          raise ActiveRecord::RecordNotFound unless assigned_company_ids.include?(company.id)

          engagement = company.current_engagement
          latest = engagement&.latest_stage1_quote
          client_quote = Pricing::ClientQuoteView.current_for(engagement)
          render json: {
            engagement_status: engagement&.status,
            latest: latest && { version: latest.version, status: latest.status, created_at: latest.created_at,
                                rejection_note: latest.rejection_note, decline_reason: latest.decline_reason },
            quote: client_quote && Pricing::ClientQuoteView.new(client_quote).json
          }
        end
      end
    end
  end
end
