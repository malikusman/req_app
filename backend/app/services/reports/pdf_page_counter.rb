# frozen_string_literal: true

module Reports
  # How many pages the PDF actually has.
  #
  # This used to be counted from the HTML instead — one `<section class="page">`
  # per page — which is only true while every section fits its sheet. When one
  # overflows, Chromium paginates it and the document silently gains a page the
  # rest of the system never hears about: the portal offers "4 pp" on a 5-page
  # brief, and the brief's own footer prints "1 / 4".
  #
  # Counting the PDF is the only way to know. The HTML count stays as the last
  # fallback, because a page count that is slightly wrong is a worse outcome than
  # a report that fails to store.
  class PdfPageCounter
    # `/Type /Page` appears once per page object. The lookahead is what keeps
    # `/Type /Pages` — the tree nodes — out of the count.
    PAGE_OBJECT = %r{/Type\s*/Page(?![s/\w])}
    # Page-tree nodes nest, so several /Count values exist and the largest is the
    # root's: the total. Only consulted when the page objects are unreadable.
    COUNT_ENTRY = %r{/Type\s*/Pages\b[^>]{0,400}?/Count\s+(\d+)}m

    def self.call(bytes:, fallback: nil)
      new(bytes: bytes, fallback: fallback).call
    end

    def initialize(bytes:, fallback: nil)
      @bytes = bytes
      @fallback = fallback
    end

    def call
      return @fallback unless pdf?

      from_page_objects || from_page_tree || @fallback
    end

    private

    def pdf?
      @bytes.is_a?(String) && @bytes.byteslice(0, 5) == "%PDF-"
    end

    def from_page_objects
      count = scan_source.scan(PAGE_OBJECT).size
      count.positive? ? count : nil
    end

    # Only reachable when the page objects sit inside compressed object streams,
    # which Chromium does not currently do — but a Gotenberg upgrade could.
    def from_page_tree
      counts = scan_source.scan(COUNT_ENTRY).flatten.map(&:to_i)
      counts.max&.then { |n| n.positive? ? n : nil }
    end

    # Binary-safe: the markers are ASCII, and forcing the encoding avoids an
    # invalid-byte-sequence error from scanning raw PDF bytes as UTF-8.
    def scan_source
      @scan_source ||= @bytes.dup.force_encoding(Encoding::BINARY)
    end
  end
end
