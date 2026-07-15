# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evidence::GraphBuilder do
  let(:company) { create(:company) }
  let!(:employee) { create(:employee, company: company, display_name: "Ava") }

  it "returns typed nodes and edges compatible with the reviewer UI" do
    graph = described_class.call(company: company)

    expect(graph[:nodes]).to include(
      hash_including(type: "employee", id: employee.id, label: "Ava")
    )
    expect(graph[:coverage]).to include(:signals, :supported_edges, :employees)
  end
end
