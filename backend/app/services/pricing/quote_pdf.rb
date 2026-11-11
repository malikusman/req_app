# frozen_string_literal: true

module Pricing
  # The quote as a document the client can keep and forward (Doc 17 §10.2):
  # rendered from the client view only, so nothing internal can reach it, made
  # into a PDF by Gotenberg and kept in storage beside the reports. Where
  # Gotenberg is down and mocks are allowed, the HTML is kept instead, as
  # reports do (Reports::PdfGenerator).
  class QuotePdf
    def self.call(quote) = new(quote).call

    # The stored document, made first if it isn't there yet.
    def self.fetch(quote)
      quote = call(quote) if quote.pdf_storage_key.blank?
      body = Storage::MinioClient.new.download(quote.pdf_storage_key)
      [body, quote.pdf_storage_key.end_with?(".pdf") ? "application/pdf" : "text/html"]
    end

    def initialize(quote)
      @quote = quote
    end

    def call
      body = Reports::PdfGenerator.call(html: html, paper: Reports::VariantSpec::PORTRAIT)
      pdf = body.start_with?("%PDF")
      key = "quotes/#{@quote.company_id}/#{@quote.engagement_id}/stage1-v#{@quote.version}.#{pdf ? 'pdf' : 'html'}"
      Storage::MinioClient.new.upload(key: key, body: body, content_type: pdf ? "application/pdf" : "text/html")
      @quote.update!(pdf_storage_key: key)
      @quote.record!("pdf_generated", detail: { key: key, pdf: pdf })
      @quote
    end

    def html
      ActionController::Base.render(template: "quotes/stage1", layout: false,
                                    locals: { quote: ClientQuoteView.new(@quote).json })
    end
  end
end
