# frozen_string_literal: true

module Api
  module V1
    module Company
      class NotificationsController < BaseController
        def index
          authorize Notification, :index?
          scope = policy_scope(Notification).order(created_at: :desc)
          unread_count = scope.unread.count
          notifications = scope.limit(per_page).offset(offset)

          render json: {
            notifications: notifications.map { |n| notification_json(n) },
            unread_count: unread_count,
            page: page,
            per_page: per_page
          }
        end

        def update
          notification = policy_scope(Notification).find(params[:id])
          authorize notification, :update?
          notification.update!(read_at: Time.current) if notification.read_at.nil?
          render json: { notification: notification_json(notification) }
        end

        def mark_all_read
          authorize Notification, :mark_all_read?
          policy_scope(Notification).unread.update_all(read_at: Time.current)
          render json: { ok: true, unread_count: 0 }
        end

        private

        def notification_json(notification)
          {
            id: notification.id,
            notification_type: notification.notification_type,
            title: notification.title,
            body: notification.body,
            action_url: notification.action_url,
            metadata: notification.metadata,
            read_at: notification.read_at,
            created_at: notification.created_at
          }
        end

        def page
          [params[:page].to_i, 1].max
        end

        def per_page
          [[params[:per_page].to_i, 20].max, 50].min
        end

        def offset
          (page - 1) * per_page
        end
      end
    end
  end
end
