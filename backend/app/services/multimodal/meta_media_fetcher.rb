# frozen_string_literal: true

require "net/http"
require "tempfile"

module Multimodal
  class MetaMediaFetcher
    def initialize(client: Whatsapp::MetaClient.new)
      @client = client
    end

    def download_to_tempfile(meta_media_id)
      raise Whatsapp::MetaClient::ApiError, "WhatsApp not configured" unless @client.configured?

      url = fetch_media_url(meta_media_id)
      binary = download_binary(url)
      ext = extension_for_meta_id(meta_media_id)
      file = Tempfile.new(["whatsapp-media", ext])
      file.binmode
      file.write(binary)
      file.rewind
      file
    end

    def fetch_and_store!(media_attachment:)
      file = download_to_tempfile(media_attachment.meta_media_id)
      key = "media/#{media_attachment.company_id}/#{media_attachment.id}/#{File.basename(file.path)}"
      Storage::MinioClient.new.upload(
        key: key,
        body: File.binread(file.path),
        content_type: media_attachment.mime_type
      )
      media_attachment.update!(storage_key: key)
      file
    ensure
      file&.close
      file&.unlink
    end

    private

    def fetch_media_url(media_id)
      token = ENV.fetch("META_WHATSAPP_TOKEN")
      version = ENV.fetch("META_API_VERSION", "v21.0")
      uri = URI("https://graph.facebook.com/#{version}/#{media_id}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{token}"
      response = http.request(request)
      body = JSON.parse(response.body)
      raise Whatsapp::MetaClient::ApiError, body.dig("error", "message") unless response.is_a?(Net::HTTPSuccess)

      body["url"]
    end

    def download_binary(url)
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{ENV.fetch('META_WHATSAPP_TOKEN')}"
      response = http.request(request)
      raise Whatsapp::MetaClient::ApiError, "media download failed" unless response.is_a?(Net::HTTPSuccess)

      response.body
    end

    def extension_for_meta_id(_media_id)
      ".bin"
    end
  end
end
