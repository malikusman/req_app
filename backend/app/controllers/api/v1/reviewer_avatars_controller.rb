# frozen_string_literal: true

module Api
  module V1
    class ReviewerAvatarsController < ApplicationController
      def show
        reviewer = ReviewerUser.find(params[:id])
        return head :forbidden unless avatar_authorized?(reviewer)
        return head :not_found if reviewer.avatar_storage_key.blank?

        data = Storage::MinioClient.new.download(reviewer.avatar_storage_key)
        send_data data, type: content_type_for_key(reviewer.avatar_storage_key), disposition: "inline"
      rescue ActiveRecord::RecordNotFound
        head :not_found
      rescue Aws::S3::Errors::NoSuchKey
        head :not_found
      end

      private

      def avatar_authorized?(reviewer)
        payload = decoded_token
        return true if payload && payload[:aud] == "platform"
        if payload && payload[:aud] == "reviewer"
          return payload[:sub].to_s.split(":").last.to_i == reviewer.id
        end
        if payload && payload[:aud] == "company"
          company_id = payload[:company_id]
          return reviewer.reviewer_assignments.active.exists?(company_id: company_id) &&
                 reviewer.published_profile?
        end

        false
      end

      def decoded_token
        token = request.headers["Authorization"]&.match(/^Bearer (.+)$/)&.captures&.first
        JsonWebToken.decode(token) if token.present?
      end

      def content_type_for_key(key)
        case File.extname(key).downcase
        when ".png" then "image/png"
        when ".webp" then "image/webp"
        when ".gif" then "image/gif"
        else "image/jpeg"
        end
      end
    end
  end
end
