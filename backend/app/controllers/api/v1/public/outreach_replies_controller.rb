# frozen_string_literal: true

module Api
  module V1
    module Public
      # The tokenised reply page for anything we asked someone outside the app.
      #
      # Resolves BOTH kinds of ask — an admin-gated clarification (ConsultantOutreach)
      # and a direct consultant follow-up question (ConsultantInfoRequest) — because
      # both mint tokens through TokenisedReply. One endpoint and one page rather than
      # two near-identical copies, which also means consolidating the two channels
      # later touches less.
      class OutreachRepliesController < ApplicationController
        rescue_from ActiveRecord::RecordNotFound, with: :not_found

        OUTREACH_REPLYABLE = %w[sent replied approved queued].freeze
        REQUEST_REPLYABLE = %w[sent awaiting_reply replied].freeze

        def show
          ask = find_ask!
          render json: { outreach: ask_json(ask) }
        end

        def create
          ask = find_ask!
          unless can_reply?(ask)
            return render json: { error: "This request is closed and no longer accepts replies." },
                          status: :unprocessable_entity
          end

          body = params[:body].to_s.strip
          return render json: { error: "Reply body is required" }, status: :unprocessable_entity if body.blank?

          record_reply!(ask, body)
          render json: { status: "received" }, status: :created
        rescue ArgumentError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        private

        def find_ask!
          ConsultantOutreach.find_by_reply_token(params[:token]) ||
            ConsultantInfoRequest.find_by_reply_token(params[:token]) ||
            raise(ActiveRecord::RecordNotFound)
        end

        def ask_json(ask)
          {
            id: ask.id,
            company_name: ask.company.display_name || ask.company.name,
            body: ask.try(:edited_body).presence || ask.body,
            status: ask.status,
            can_reply: can_reply?(ask)
          }
        end

        def can_reply?(ask)
          if ask.is_a?(ConsultantOutreach)
            OUTREACH_REPLYABLE.include?(ask.status)
          else
            REQUEST_REPLYABLE.include?(ask.status)
          end
        end

        def record_reply!(ask, body)
          if ask.is_a?(ConsultantOutreach)
            Outreaches::RecordReplyService.call(outreach: ask, body: body, channel: "email")
          else
            # Shares the recorder with the WhatsApp path, so an emailed answer also
            # advances the consultant's requirement loop.
            ConsultantFollowup::RecordReplyService.call(request: ask, body: body, channel: "email")
          end
        end

        def not_found
          render json: { error: "This link is invalid or expired." }, status: :not_found
        end
      end
    end
  end
end
