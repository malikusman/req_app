# frozen_string_literal: true

module Pricing
  # A Stage 1 quote as the client sees it (Doc 17 §10, Doc 21 §10): the price,
  # its lines, what is and isn't included, the additional-participant rate, its
  # validity, payment terms and the terms it is governed by.
  #
  # Built from a list of fields, never from the record: cost basis, hours,
  # margin, rates, override reasons and the administrator's explanation are
  # INTERNAL_COMMERCIAL and never reach a client view, a client document or a
  # consultant (Doc 05 §4.2, §18; Doc 17 §15). The portal, the PDF, the
  # consultant's view and the dashboard all use this.
  class ClientQuoteView
    # What the client may see of each line.
    LINE_FIELDS = %w[key label quantity unit_amount amount detail].freeze
    SCOPE_FIELDS = %w[what_is_included what_is_not_included participants_and_departments deliverable
                      additional_participants what_happens_next validity].freeze
    CLIENT_STATUSES = %w[ISSUED ACCEPTED DECLINED EXPIRED].freeze

    # The quote the client should see now: the accepted one; otherwise the
    # newest, if it has been sent to them. While a fresh version is being
    # prepared, there is nothing to show.
    def self.current_for(engagement)
      return nil unless engagement

      engagement.accepted_stage1_quote || engagement.latest_stage1_quote&.then { |q| CLIENT_STATUSES.include?(q.status) ? q : nil }
    end

    def initialize(quote, viewer: nil)
      @quote = quote
      @viewer = viewer
    end

    def json
      q = @quote
      stage1 = q.rate_card_version.stage1
      {
        id: q.id, version: q.version, status: q.status, currency: q.currency,
        company_name: q.company.display_name.presence || q.company.name,
        line_items: q.line_items.map { |line| line.slice(*LINE_FIELDS) },
        subtotal: q.subtotal.to_s("F"), tax_rate: q.tax_rate.to_s("F"), tax_amount: q.tax_amount.to_s("F"),
        total: q.total.to_s("F"), additional_participant_rate: q.additional_participant_rate.to_s("F"),
        participants_included: q.participants_included, deep_dives_included: q.deep_dives_included,
        departments: Array(q.inputs["departments"]).map { |d| { name: d["name"], count: d["count"] } },
        scope: q.client_scope.slice(*SCOPE_FIELDS),
        payment_terms: stage1["payment_terms_text"], terms_reference: stage1["terms_reference_text"],
        issued_at: q.issued_at, valid_until: q.valid_until, past_validity: q.past_validity?,
        accepted_at: q.accepted_at, accepted_by: q.accepted_by&.name,
        declined_at: q.declined_at,
        can_decide: can_decide?
      }
    end

    private

    # Only the key user accepts or declines (Doc 17 §10.3, Doc 21 §44).
    def can_decide?
      @viewer.is_a?(CompanyUser) && @quote.engagement.key_user_id == @viewer.id && @quote.issued? && !@quote.past_validity?
    end
  end
end
