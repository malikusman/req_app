# frozen_string_literal: true

module Api
  module V1
    class ReviewerCvsController < ApplicationController
      def show
        reviewer = ReviewerUser.find(params[:id])
        return head :forbidden unless cv_authorized?(reviewer)
        return head :not_found if reviewer.cv_storage_key.blank?

        data = Storage::MinioClient.new.download(reviewer.cv_storage_key)
        send_data data,
                  type: reviewer.cv_content_type.presence || "application/octet-stream",
                  filename: reviewer.cv_filename.presence || "reviewer-cv",
                  disposition: "inline"
      rescue ActiveRecord::RecordNotFound, Aws::S3::Errors::NoSuchKey
        head :not_found
      end

      private

      def cv_authorized?(reviewer)
        payload = decoded_token
        return true if payload && payload[:aud] == "platform"
        return payload[:sub].to_s.split(":").last.to_i == reviewer.id if payload && payload[:aud] == "reviewer"

        false
      end

      def decoded_token
        token = request.headers["Authorization"]&.match(/^Bearer (.+)$/)&.captures&.first
        JsonWebToken.decode(token) if token.present?
      end
    end
  end
end
