# frozen_string_literal: true

module Api
  module V1
    module Public
      class OutreachRepliesController < ApplicationController
        rescue_from ActiveRecord::RecordNotFound, with: :not_found

        def show
          outreach = find_outreach!
          render json: {
            outreach: {
              id: outreach.id,
              company_name: outreach.company.display_name || outreach.company.name,
              body: outreach.edited_body.presence || outreach.body,
              status: outreach.status,
              can_reply: can_reply?(outreach)
            }
          }
        end

        def create
          outreach = find_outreach!
          unless can_reply?(outreach)
            return render json: { error: "This clarification is closed and no longer accepts replies." },
                           status: :unprocessable_entity
          end

          body = params.require(:body).to_s.strip
          return render json: { error: "Reply body is required" }, status: :unprocessable_entity if body.blank?

          Outreaches::RecordReplyService.call(
            outreach: outreach,
            body: body,
            channel: "email"
          )
          render json: { status: "received" }, status: :created
        rescue ArgumentError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        private

        def find_outreach!
          digest = Digest::SHA256.hexdigest(params[:token].to_s)
          ReviewerOutreach.find_by!(reply_token_digest: digest)
        end

        def can_reply?(outreach)
          outreach.status.in?(%w[sent replied approved queued])
        end

        def not_found
          render json: { error: "Clarification link is invalid or expired." }, status: :not_found
        end
      end
    end
  end
end
