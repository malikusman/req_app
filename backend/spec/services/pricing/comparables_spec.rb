# frozen_string_literal: true

require "rails_helper"

# Similar past Stage 1 work for the administrator (Doc 17 §9.1): accepted
# quotes of a similar size from other engagements, no client named.
RSpec.describe Pricing::Comparables do
  let(:engagement) { create(:engagement) }

  def accepted(participants)
    create(:quote, :issued, participants_included: participants).tap do |quote|
      quote.update!(status: "ACCEPTED", accepted_by: create(:company_user, company: quote.company), accepted_at: Time.current)
    end
  end

  it "lists accepted quotes within half the size either way, saying actual hours aren't recorded" do
    near = accepted(8)
    accepted(20)
    create(:quote, participants_included: 8)

    result = described_class.for(engagement, 10)

    expect(result.size).to eq(1)
    expect(result.first).to include("participants" => 8, "fee" => near.subtotal.to_s("F"), "actual_hours" => nil)
    expect(result.first.keys).not_to include("company", "company_name")
  end

  it "leaves out the engagement's own quotes" do
    quote = accepted(10)
    expect(described_class.for(quote.engagement, 10)).to eq([])
  end
end
