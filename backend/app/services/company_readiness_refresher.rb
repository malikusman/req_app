# frozen_string_literal: true

class CompanyReadinessRefresher
  def self.call(company)
    new(company).call
  end

  def initialize(company)
    @company = company
  end

  def call
    interviewed = @company.employees.where(participation_status: "completed").count
    departments = @company.employees.where(participation_status: "completed")
                          .where.not(department: [nil, ""])
                          .distinct.count(:department)

    completed_conv_ids = @company.conversations.where(status: "completed").select(:id)
    whatsapp_multimodal = MediaAttachment.where(conversation_id: completed_conv_ids, status: "ready")
                                         .distinct.count(:conversation_id)
    ready_docs = @company.documents.where(status: "ready")
    portal_documents = ready_docs.count
    document_departments = ready_docs.where.not(department: [nil, ""]).distinct.count(:department)

    @company.update!(
      report_readiness_breakdown: {
        "employees_interviewed" => interviewed,
        "departments_represented" => departments,
        "confirmed_patterns" => @company.patterns.where(status: "confirmed").count,
        "multimodal_contributions" => whatsapp_multimodal + portal_documents,
        "ready_documents" => portal_documents,
        "document_departments" => document_departments,
        "insights_count" => ConversationInsight.where(company_id: @company.id).count
      }
    )

    ReportReadinessCalculator.call(@company)
  end
end
