# frozen_string_literal: true

# Builders for the synthesis specs: findings as employee interviews leave them,
# and a leadership context with its strategic findings as P04 leaves it.
module SynthesisHelpers
  def synthesis_finding(company:, role:, department: "Sales", hours: nil, employee: nil, **attrs)
    employee ||= create(:employee, company: company, role_title: role, department: department)
    company.findings.create!(
      {
        employee: employee, source_key: SecureRandom.hex(4), department: department, role_title: role,
        area: "work #{SecureRandom.hex(2)}", title: "Work #{SecureRandom.hex(2)}", friction: "It snags",
        effort_type: "active", annual_hours_min: hours&.first, annual_hours_max: hours&.last,
        evidence: { "conversation_id" => nil, "slots" => { "friction" => 4 } }
      }.merge(attrs)
    )
  end

  def leadership_context(engagement:, content: {}, consultant_private: {}, name: "Layla Haddad")
    participant = create(:engagement_participant, engagement: engagement, participant_type: "KEY_PERSON", name: name)
    session = create(:conversation_session, participant: participant, state: "COMPLETE")
    ManagementDiscoveryContext.create!(
      company: engagement.company, engagement: engagement, participant: participant, session: session,
      status: "COMPLETE", schema_version: "MDC.v1", content: content, consultant_private: consultant_private
    )
  end

  def strategic_finding(context, statement:, importance: "HIGH", category: "PROCESS", **attrs)
    context.strategic_findings.create!(
      {
        company: context.company, engagement: context.engagement, category: category, scope: "DEPARTMENT",
        statement: statement, source_basis: "MANAGEMENT_STATEMENT", fact_status: "REPORTED",
        management_importance: importance, evidence: ["t2"]
      }.merge(attrs)
    )
  end
end

RSpec.configure { |config| config.include SynthesisHelpers }
