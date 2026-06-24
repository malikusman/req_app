# frozen_string_literal: true

namespace :multimodal do
  desc "Simulate WhatsApp voice note PHONE=+1... (dev, no Meta media download)"
  task simulate_voice: :environment do
    phone = ENV.fetch("PHONE")
    employee = Employee.find_by!(phone_e164: phone)
    conversation = employee.conversations.where(status: %w[discovery onboarding]).order(created_at: :desc).first
    conversation.update!(status: "discovery") unless conversation.discovery?
    employee.update!(onboarding_step: "verified", participation_status: "started")

    message = conversation.messages.create!(
      direction: "inbound",
      message_type: "audio",
      processing_status: "pending",
      external_id: "sim-audio-#{SecureRandom.hex(4)}"
    )

    attachment = MediaAttachment.create!(
      message: message,
      company: employee.company,
      employee: employee,
      conversation: conversation,
      attachment_type: "audio",
      mime_type: "audio/ogg",
      status: "pending",
      storage_key: "dev/simulated/#{SecureRandom.hex(8)}.ogg"
    )

    lang = employee.preferred_language.presence || employee.company.locale
    extracted = Openai::Client.new.transcribe_audio(file_path: "/dev/null", language: lang)
    attachment.update!(status: "ready", extracted_text: extracted)
    message.update!(body: extracted, processing_status: "ready")
    conversation.update!(state_snapshot: conversation.state_snapshot.merge("had_multimodal" => true))

    handler = Whatsapp::DiscoveryHandler.new(employee: employee, conversation: conversation)
    handler.process_extracted_text(extracted, inbound_message: message)
    puts "Transcript: #{extracted}"
    puts "Check Rails logs for assistant reply."
  end

  desc "Upload MinIO placeholders for dev/simulated media missing from storage"
  task backfill_dev_storage: :environment do
    scope = MediaAttachment.where(status: "ready").where("storage_key LIKE ? OR storage_key IS NOT NULL", "dev/simulated/%")
    count = 0
    scope.find_each do |attachment|
      begin
        Storage::MinioClient.new.download(attachment.storage_key)
      rescue Aws::S3::Errors::NoSuchKey
        Multimodal::DevStorageBackfill.call(attachment)
        count += 1
        puts "Backfilled attachment ##{attachment.id} (#{attachment.attachment_type})"
      end
    end
    puts "Done. Backfilled #{count} attachment(s)."
  end
end
