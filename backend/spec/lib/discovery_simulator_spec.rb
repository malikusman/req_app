# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("lib/discovery_simulator")

RSpec.describe DiscoverySimulator do
  describe ".purge_employee!" do
    # discovery_packages FKs to conversations.id with no ON DELETE CASCADE, and
    # Conversation had no `has_many :discovery_packages` telling Rails to clean them
    # up either. Deleting a conversation that still has a package raised a bare
    # ActiveRecord::InvalidForeignKey instead of a clean purge -- this reproduces
    # exactly that shape.
    it "clears a conversation's discovery package and its dependents before deleting the conversation" do
      company = create(:company)
      employee = create(:employee, company: company)
      conversation = create(:conversation, employee: employee, company: company, status: "completed")
      package = DiscoveryPackage.create!(
        conversation: conversation, employee: employee, company: company,
        version: 1, status: "ready", recommendation: "Automate the match."
      )
      item = package.discovery_package_items.create!(
        kind: "issue", title: "Manual verification", body: "line-by-line", status: "proposed"
      )
      consultant = create(:consultant_user)
      requirement = package.consultant_requirements.create!(
        consultant_user: consultant, employee: employee, company: company,
        statement: "Who signs off?", max_questions: 3
      )
      question = package.discovery_followup_questions.create!(
        consultant_requirement: requirement, body: "Who signs off on a mismatch?",
        status: "drafted", queue_position: 1
      )

      expect { described_class.purge_employee!(employee, company: company) }.not_to raise_error

      expect(DiscoveryPackage.exists?(package.id)).to be false
      expect(DiscoveryPackageItem.exists?(item.id)).to be false
      expect(ConsultantRequirement.exists?(requirement.id)).to be false
      expect(DiscoveryFollowupQuestion.exists?(question.id)).to be false
      expect(Conversation.exists?(conversation.id)).to be false
    end

    it "still purges an employee with no discovery package at all" do
      company = create(:company)
      employee = create(:employee, company: company)
      create(:conversation, employee: employee, company: company, status: "completed")

      expect { described_class.purge_employee!(employee, company: company) }.not_to raise_error
      expect(Employee.exists?(employee.id)).to be false
    end
  end
end
