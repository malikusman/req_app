# frozen_string_literal: true

class ParseDocumentJob < ApplicationJob
  queue_as :default

  def perform(document_id)
    Multimodal::ParseDocumentService.call(document_id)
  end
end
