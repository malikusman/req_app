# frozen_string_literal: true

module KeyPerson
  # Documents in a conversation with leadership (Doc 08 §14, Doc 14 §11): the
  # specific ones the participant mentioned, asked for together at the end, at
  # most three; what they upload, now or later; and what they say they can't
  # share.
  #
  # An upload is stored as it came and linked to its request. It is never
  # ingested or analysed here (see Document::LEADERSHIP_SOURCE): consultants
  # read it.
  class Documents
    REASON = "Mentioned in the conversation with leadership"

    def initialize(session)
      @session = session
    end

    # The assistant has just asked for them: one request per document named.
    def open_requests!(instruction)
      mentioned = Array(@session.state_snapshot["documents_mentioned"])
      Array(instruction["documents"]).each do |description|
        next if requests.exists?(requested_item: description)

        evidence = mentioned.find { |d| d["description"] == description }&.dig("evidence")
        requests.create!(company: @session.company, requested_item: description, reason: REASON,
                         evidence: [evidence].compact)
      end
    end

    # They said they can't or won't share them: no reminders (Doc 14 §11.4).
    def decline_open!
      requests.open.update_all(status: "DECLINED", updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end

    def upload!(file, request_id: nil, uploaded_by: nil)
      raise ArgumentError, "Choose a file to upload." unless file.respond_to?(:read)

      content_type = file.content_type.to_s
      raise ArgumentError, "That kind of file can't be uploaded. Try a PDF, Word, Excel or a photo." unless Document.allowed_content_type?(content_type)

      body = file.read
      raise ArgumentError, "That file is too large (#{Document::MAX_BYTES / 1.megabyte} MB at most)." if body.bytesize > Document::MAX_BYTES

      request = request_id.present? ? requests.find(request_id) : nil
      filename = file.original_filename.to_s.presence || "upload"
      company = @session.company
      key = "documents/#{company.id}/leadership/#{SecureRandom.uuid}/#{filename}"
      Storage::MinioClient.new.upload(key: key, body: body, content_type: content_type)

      Document.transaction do
        document = company.documents.create!(
          source: Document::LEADERSHIP_SOURCE, document_request: request, uploaded_by_company_user: uploaded_by,
          filename: filename, content_type: content_type, byte_size: body.bytesize, storage_key: key,
          status: "uploaded", document_type: "other", sensitivity: "confidential", consultant_visible: true,
          metadata: { "conversation_session_id" => @session.id, "engagement_participant_id" => @session.participant.id }
        )
        request&.update!(status: "RECEIVED")
        document
      end
    end

    def json
      requests.order(:id).map do |r|
        { id: r.id, requested_item: r.requested_item, status: r.status, uploaded: r.documents.count }
      end
    end

    private

    def requests = DocumentRequest.where(conversation_session_id: @session.id)
  end
end
