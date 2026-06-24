# frozen_string_literal: true

module Multimodal
  # Dev/simulated WhatsApp media records metadata without uploading bytes.
  # Backfill MinIO so download endpoints work in local development.
  class DevStorageBackfill
    MINIMAL_JPEG = Base64.decode64(
      "/9j/4AAQSkZJRgABAQEASABIAAD/2wCEAAEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEB" \
      "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEB" \
      "AQEBAQH/wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAAA//EABQQAQAAAAAAAAAA" \
      "AAAAAAAAAAD/2gAIAQEAAQUCf//EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQMBAT8Bf//E" \
      "ABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQIBAT8Bf//Z"
    ).freeze

    MINIMAL_PDF = <<~PDF.freeze
      %PDF-1.1
      1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
      2 0 obj<</Type/Pages/Count 1/Kids[3 0 R]>>endobj
      3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]>>endobj
      xref
      0 4
      0000000000 65535 f
      0000000009 00000 n
      0000000052 00000 n
      0000000101 00000 n
      trailer<</Size 4/Root 1 0 R>>
      startxref
      178
      %%EOF
    PDF

    MINIMAL_OGG = Base64.decode64("T2dnUwACAAAAAAAAAAA=").freeze

    def self.call(attachment)
      new(attachment).call
    end

    def self.fixture_available?(attachment)
      new(attachment).send(:fixture_path).present?
    end

    def self.upload_placeholder!(attachment)
      new(attachment).upload_placeholder!
    end

    def initialize(attachment)
      @attachment = attachment
    end

    def call
      upload_placeholder!
      @attachment.update!(storage_key: @key)
      true
    end

    def upload_placeholder!
      body, content_type = placeholder_bytes
      @key = self.class.storage_key_for(@attachment)
      Storage::MinioClient.new.upload(key: @key, body: body, content_type: content_type)
      @key
    end

    def self.storage_key_for(attachment)
      ext = extension_for(attachment)
      "dev/simulated/#{attachment.id}#{ext}"
    end

    def self.extension_for(attachment)
      case attachment.attachment_type
      when "audio" then ".ogg"
      when "image" then ".jpg"
      when "document" then ".pdf"
      else ".bin"
      end
    end

    private

    def placeholder_bytes
      fixture = fixture_path
      if fixture&.exist?
        return [File.binread(fixture), content_type_for_fixture(fixture)]
      end

      case @attachment.attachment_type
      when "image"
        [MINIMAL_JPEG, @attachment.mime_type.presence || "image/jpeg"]
      when "document"
        [MINIMAL_PDF, @attachment.mime_type.presence || "application/pdf"]
      when "audio"
        [MINIMAL_OGG, @attachment.mime_type.presence || "audio/ogg"]
      else
        ["", "application/octet-stream"]
      end
    end

    def fixture_path
      roots = [
        Rails.root.join("docs/manual-test"),
        Pathname.new("/docs/manual-test")
      ]
      summary = @attachment.structured_insights.to_h.fetch("summary", "").to_s.downcase
      filename = @attachment.metadata.to_h.fetch("filename", "").to_s.downcase

      roots.each do |root|
        next unless root.exist?

        if @attachment.attachment_type == "image" ||
           summary.include?("invoice") || summary.include?("sap")
          path = root.join("sap-invoice-entry.jpg")
          return path if path.exist?
        end

        if @attachment.attachment_type == "document" ||
           filename.include?("checklist") || summary.include?("month-end") || summary.include?("close")
          path = root.join("month-end-close-checklist.pdf")
          return path if path.exist?
        end
      end

      nil
    end

    def content_type_for_fixture(path)
      case File.extname(path).downcase
      when ".jpg", ".jpeg" then "image/jpeg"
      when ".pdf" then "application/pdf"
      when ".png" then "image/png"
      else @attachment.mime_type.presence || "application/octet-stream"
      end
    end
  end
end
