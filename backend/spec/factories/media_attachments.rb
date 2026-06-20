# frozen_string_literal: true

FactoryBot.define do
  factory :media_attachment do
    message
    company { message.conversation.employee.company }
    employee { message.conversation.employee }
    conversation { message.conversation }
    attachment_type { "image" }
    mime_type { "image/jpeg" }
    status { "pending" }
    sequence(:storage_key) { |n| "media/test/#{n}.jpg" }
  end
end
