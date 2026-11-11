# frozen_string_literal: true

require "rails_helper"

# Doc 06 §1.2 and §6: what synthesis stores is versioned, never overwritten,
# keeps raw and de-duplicated effort apart, and keeps management importance
# apart from platform priority.
RSpec.describe "Synthesis records" do
  let(:company) { create(:company, :onboarded) }
  let(:engagement) { create(:engagement, company: company) }
  let(:finding) { synthesis_finding(company: company, role: "Sales Coordinator", hours: [100, 150]) }

  def cluster(**attrs)
    ProcessCluster.create!({ company: company, engagement: engagement, cluster_key: "cl-1", name: "Quotations",
                             cluster_type: "SHARED_IDENTICAL", schema_version: ProcessCluster::SCHEMA_VERSION }
                             .merge(attrs))
  end

  describe "versioning" do
    it "makes a new version on change, links it to the old one and keeps the old one readable" do
      original = cluster
      original.members.create!(finding: finding, employee: finding.employee,
                               member_digest: ProcessClusterMember.digest_for(finding))

      revised = original.revise!(name: "Customer quotations", status: "APPROVED")

      expect(revised.version).to eq(2)
      expect(revised.parent_version).to eq(original)
      expect(revised.name).to eq("Customer quotations")
      expect(revised.finding_ids).to eq([finding.id])
      expect(original.reload.status).to eq("SUPERSEDED")
      expect(original.name).to eq("Quotations")
      expect(ProcessCluster.current.where(cluster_key: "cl-1")).to eq([revised])
    end

    it "refuses to revise a version that is already superseded" do
      original = cluster
      original.revise!(name: "Newer")

      expect { original.reload.revise!(name: "Stale edit") }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "keeps rejected output rather than deleting it" do
      opportunity = ConsultancyOpportunity.create!(
        company: company, engagement: engagement, opportunity_key: "op-1", level: "PROCESS", category: "INTEGRATION",
        title: "One source for prices", problem_statement: "Prices are kept in three places.",
        recommended_next_action: "DEEP_DIVE", confidence: "MEDIUM", schema_version: ConsultancyOpportunity::SCHEMA_VERSION
      )
      rejected = opportunity.revise!(status: "REJECTED")

      expect(ConsultancyOpportunity.where(opportunity_key: "op-1").count).to eq(2)
      expect(ConsultancyOpportunity.current.find_by(opportunity_key: "op-1")).to eq(rejected)
    end
  end

  describe "a decision log that cannot be rewritten" do
    it "requires a reason and is read-only once written" do
      consultant = create(:consultant_user)
      original = cluster
      expect do
        SynthesisDecision.create!(company: company, engagement: engagement, action: "APPROVE_CLUSTER",
                                  subject: original, actor: consultant, rationale: "")
      end.to raise_error(ActiveRecord::RecordInvalid)

      decision = SynthesisDecision.create!(company: company, engagement: engagement, action: "APPROVE_CLUSTER",
                                           subject: original, actor: consultant, rationale: "Same quotes, two branches")
      expect { decision.update!(rationale: "changed") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end

  describe "effort" do
    it "keeps raw and de-duplicated figures apart, and a consultant override wins only with a reason" do
      normalization = EffortNormalization.create!(
        company: company, engagement: engagement, process_cluster: cluster, raw_min: 200, raw_max: 300,
        dedup_min: 100, dedup_max: 150, method_version: "EN.v1"
      )
      expect([normalization.hours_min, normalization.hours_max]).to eq([100, 150])

      normalization.consultant_min = 120
      normalization.consultant_max = 160
      expect(normalization).not_to be_valid

      normalization.override_rationale = "Branch B's volumes are lower than stated"
      normalization.save!
      expect([normalization.hours_min, normalization.hours_max]).to eq([120, 160])
      expect([normalization.raw_min, normalization.raw_max]).to eq([200, 300])
    end

    it "rejects an override below zero or upside down" do
      normalization = EffortNormalization.new(company: company, engagement: engagement, process_cluster: cluster,
                                              method_version: "EN.v1", override_rationale: "x")
      normalization.assign_attributes(consultant_min: -5, consultant_max: 10)
      expect(normalization).not_to be_valid
      normalization.assign_attributes(consultant_min: 20, consultant_max: 10)
      expect(normalization).not_to be_valid
    end
  end

  describe "relationships" do
    let(:other) { synthesis_finding(company: company, role: "Sales Coordinator", hours: [80, 120]) }

    def relationship(**attrs)
      ProcessRelationship.new({ company: company, engagement: engagement, from_finding: finding, to_finding: other,
                                pair_digest: "d", relationship_type: "SAME_PROCESS", confidence: "HIGH",
                                recommendation: "AUTO_CLUSTER", schema_version: ProcessRelationship::SCHEMA_VERSION }
                                .merge(attrs))
    end

    it "never clusters at LOW confidence" do
      expect(relationship(confidence: "LOW", recommendation: "PROVISIONAL_CLUSTER")).not_to be_valid
      expect(relationship(confidence: "LOW", recommendation: "KEEP_SEPARATE")).to be_valid
    end

    it "queues fallbacks and unsettled pairs for the consultant" do
      expect(relationship(origin: "FALLBACK", relationship_type: "INDEPENDENT",
                          recommendation: "KEEP_SEPARATE")).to be_needs_review
      expect(relationship(recommendation: "CLARIFY", confidence: "MEDIUM")).to be_needs_review
      expect(relationship).not_to be_needs_review
    end
  end

  describe "priorities" do
    it "stores management importance and platform priority as separate values" do
      opportunity = ConsultancyOpportunity.create!(
        company: company, engagement: engagement, opportunity_key: "op-2", level: "DEPARTMENT", category: "REPORTING",
        title: "Month-end pack", problem_statement: "Assembled by hand.", recommended_next_action: "DIRECT_FINDING",
        confidence: "MEDIUM", management_importance: "HIGH", platform_priority: "LOW",
        schema_version: ConsultancyOpportunity::SCHEMA_VERSION
      )
      expect(opportunity.reload.management_importance).to eq("HIGH")
      expect(opportunity.platform_priority).to eq("LOW")
    end
  end

  describe "leadership validations" do
    it "marks leadership's statement contradicted only where a material difference was found" do
      context = leadership_context(engagement: engagement)
      sf = strategic_finding(context, statement: "Finance is slow")
      validation = ManagementValidation.new(company: company, engagement: engagement, strategic_finding: sf,
                                            strategic_finding_version: sf.version, management_view: sf.statement,
                                            relationship: "POINTS_ELSEWHERE", material: false,
                                            schema_version: ManagementValidation::SCHEMA_VERSION)
      expect(validation.fact_status).to eq("REPORTED")
      validation.material = true
      expect(validation.fact_status).to eq("CONTRADICTED")
    end
  end

  describe "staleness" do
    it "notices when a clustered finding is rebuilt" do
      member = cluster.members.create!(finding: finding, member_digest: ProcessClusterMember.digest_for(finding))
      expect(member).not_to be_stale

      finding.update!(what_happens_now: "Now done another way")
      expect(member.reload).to be_stale
    end
  end
end
