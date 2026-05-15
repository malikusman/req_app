# frozen_string_literal: true

namespace :whatsapp do
  desc "Simulate inbound WhatsApp text (dev) PHONE=+14155551234 TEXT='hello'"
  task simulate: :environment do
    phone = ENV.fetch("PHONE")
    text = ENV.fetch("TEXT", "Hello")
    digits = phone.gsub(/\D/, "")

    payload = {
      "entry" => [{
        "changes" => [{
          "value" => {
            "messages" => [{
              "id" => "sim-#{SecureRandom.hex(8)}",
              "from" => digits,
              "type" => "text",
              "text" => { "body" => text }
            }]
          }
        }]
      }]
    }

    Whatsapp::InboundProcessor.new(payload).process
    puts "Processed simulated message from #{phone}: #{text}"
  end
end
