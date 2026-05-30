# frozen_string_literal: true

module CompanyInfoRequests
  class ReplyService
    def self.call(request:, sender:, body:, file: nil, uploaded_by: nil)
      new(request: request, sender: sender, body: body, file: file, uploaded_by: uploaded_by).call
    end

    def initialize(request:, sender:, body:, file: nil, uploaded_by: nil)
      @request = request
      @sender = sender
      @body = body
      @file = file
      @uploaded_by = uploaded_by
    end

    def call
      document = nil
      if @file.respond_to?(:read)
        document = upload_document!(@file)
      end

      reply = @request.company_info_request_replies.create!(
        sender: @sender,
        body: @body,
        document: document
      )

      if @sender.is_a?(CompanyUser)
        @request.update!(status: "answered")
        NotificationService.notify_company_info_request_replied(request: @request, reply: reply)
      end

      reply
    end

    private

    def upload_document!(file)
      company = @request.company
      filename = file.original_filename.presence || "upload.bin"
      storage_key = "documents/#{company.id}/#{SecureRandom.uuid}/#{filename}"
      body = file.read
      Storage::MinioClient.new.upload(key: storage_key, body: body, content_type: file.content_type)

      doc = company.documents.create!(
        uploaded_by_company_user: @uploaded_by,
        source: "company_portal_upload",
        filename: filename,
        content_type: file.content_type,
        byte_size: body.bytesize,
        storage_key: storage_key,
        status: "pending",
        metadata: { "upload_context" => "info_request_reply", "company_info_request_id" => @request.id }
      )
      ParseDocumentJob.perform_later(doc.id)
      doc
    end
  end
end
