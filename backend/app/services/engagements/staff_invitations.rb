# frozen_string_literal: true

module Engagements
  # Whether the client's staff can be invited, and whether an invitation goes
  # past what the Stage 1 price covers (Doc 14 §4.1, Doc 07 §7, Doc 17 §2.1,
  # §12). Every staff invitation goes through InviteEmployeeService, which asks
  # here first — the portal, a bulk upload, or a platform user impersonating
  # the client.
  #
  # Staff are invited once the key user has accepted the Stage 1 price. From
  # then, each person beyond the number the price covers is charged at the
  # additional-participant rate agreed up front, so inviting them needs the
  # client to confirm it — never a surprise — and they are flagged
  # added_after_pricing. Who counts: staff invited since the engagement began
  # who haven't declined, so a swap within the number is free.
  #
  # A company from before engagements has no engagement and is unaffected.
  class StaffInvitations
    class NotYetAllowed < StandardError; end

    class ConfirmationRequired < StandardError
      attr_reader :details

      def initialize(details)
        @details = details
        super(details[:message])
      end
    end

    OPEN_STATUSES = %w[STAGE_1_ACTIVE].freeze

    def initialize(company)
      @company = company
      @engagement = company.current_engagement
    end

    # How many of `adding` new staff go beyond the price. Raises if they can't
    # be invited yet, or if any go beyond it and the client hasn't confirmed.
    def check!(adding: 1, confirmed: false)
      return 0 unless @engagement
      raise NotYetAllowed, locked_message unless OPEN_STATUSES.include?(@engagement.status)

      extra = extra_for(adding)
      raise ConfirmationRequired, details(adding, extra) if extra.positive? && !confirmed

      extra
    end

    def open? = @engagement.nil? || OPEN_STATUSES.include?(@engagement.status)

    def included = quote&.participants_included

    def invited
      return 0 unless @engagement

      @company.employees.where(invited_at: @engagement.created_at..).where.not(participation_status: "declined").count
    end

    # The participant row for an invited person past the price: the planned
    # one if they were planned, otherwise a new one, flagged so the charge is
    # visible (Doc 06 §3.6).
    def flag_added!(employee, planned: nil)
      return unless @engagement

      participant = planned || @engagement.participants.find_by(employee: employee) ||
                    @engagement.participants.new(company: @company, participant_type: "EMPLOYEE", source: "INVITED",
                                                 name: employee.display_name.presence || employee.phone_e164,
                                                 department: employee.department, email: employee.email,
                                                 employee: employee)
      participant.update!(added_after_pricing: true, employee: employee)
    end

    def summary
      return { open: true } unless @engagement

      { open: open?, message: (locked_message unless open?), included: included, invited: invited,
        rate: quote&.additional_participant_rate&.to_s("F"), currency: quote&.currency }
    end

    private

    def quote = @engagement&.accepted_stage1_quote

    def extra_for(adding)
      return 0 unless included

      [invited + adding - included, 0].max - [invited - included, 0].max
    end

    def locked_message
      return "This engagement is closed." if @engagement.closed?

      "Your team can be invited once the Stage 1 proposal is accepted."
    end

    def details(adding, extra)
      rate = Pricing::Money.format(quote.additional_participant_rate, quote.currency)
      { code: "confirm_additional", included: included, invited: invited, adding: adding, extra: extra,
        rate: quote.additional_participant_rate.to_s("F"), currency: quote.currency,
        message: "Your Stage 1 proposal covers #{included} people and #{invited} are invited. " \
                 "#{extra == 1 ? 'This person is' : "#{extra} of these people are"} additional, at #{rate} each." }
    end
  end
end
