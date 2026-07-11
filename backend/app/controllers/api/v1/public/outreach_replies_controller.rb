# frozen_string_literal: true

module Api
  module V1
    module Public
      class OutreachRepliesController < ApplicationController
        def show
          outreach = find_outreach!
          render json: {
            outreach: {
              id: outreach.id,
              company_name: outreach.company.display_name || outreach.company.name,
              body: outreach.edited_body.presence || outreach.body,
              status: outreach.status
            }
          }
        end

        def create
          outreach = find_outreach!
          Outreaches::RecordReplyService.call(
            outreach: outreach,
            body: params.require(:body),
            channel: "email"
          )
          render json: { status: "received" }, status: :created
        end

        private

        def find_outreach!
          digest = Digest::SHA256.hexdigest(params[:token].to_s)
          ReviewerOutreach.find_by!(reply_token_digest: digest)
        end
      end
    end
  end
end
