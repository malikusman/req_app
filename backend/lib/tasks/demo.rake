# frozen_string_literal: true

namespace :demo do
  desc "Seed full end-to-end demo scenario (platform/company/reviewer/employees/reports)"
  task seed_full: :environment do
    load Rails.root.join("db/seeds.rb")

    platform = PlatformUser.find_by!(email: "admin@reqapp.local")
    company = Company.find_by!(slug: "acme-corp")
    company_admin = CompanyUser.find_by!(company: company, email: "admin@acme.local")
    reviewer = ReviewerUser.find_by!(email: "reviewer@reqapp.local")

    company.update!(
      portal_onboarding_completed_at: company.portal_onboarding_completed_at || Time.current,
      settings: company.settings.merge("allow_early_report" => true, "skip_platform_review" => false)
    )

    # 4 employees with completed discovery conversations
    employee_rows = [
      { name: "Ayesha Khan", department: "operations", phone: "+14155550101" },
      { name: "Imran Ali", department: "finance", phone: "+14155550102" },
      { name: "Sara Malik", department: "hr", phone: "+14155550103" },
      { name: "Bilal Ahmed", department: "sales", phone: "+14155550104" }
    ]

    employee_rows.each_with_index do |row, idx|
      employee = company.employees.find_or_initialize_by(phone_e164: row[:phone])
      employee.assign_attributes(
        display_name: row[:name],
        department: row[:department],
        participation_status: "completed",
        onboarding_step: "verified",
        invited_at: employee.invited_at || (5.days.ago + idx.hours),
        completed_at: employee.completed_at || (2.days.ago + idx.hours),
        last_active_at: Time.current,
        invited_by_company_user: company_admin
      )
      employee.save!

      conversation = company.conversations.find_or_initialize_by(employee_id: employee.id, status: "completed")
      conversation.assign_attributes(
        started_at: conversation.started_at || (4.days.ago + idx.hours),
        completed_at: conversation.completed_at || (1.day.ago + idx.hours),
        last_activity_at: Time.current,
        question_count: [conversation.question_count.to_i, 8].max
      )
      conversation.save!

      [
        ["inbound", "We spend too much time waiting for approvals."],
        ["outbound", "Where do approvals usually get stuck?"],
        ["inbound", "Manager and finance handoffs are manual in spreadsheets."],
        ["outbound", "What impact does that have on daily work?"]
      ].each_with_index do |(direction, body), message_idx|
        Message.find_or_create_by!(external_id: "demo-#{employee.id}-#{message_idx}") do |m|
          m.conversation = conversation
          m.direction = direction
          m.message_type = "text"
          m.body = body
          m.processing_status = "ready"
          m.reviewer_followup = false
        end
      end
    end

    # Email-invite example employee for non-WhatsApp invite flow.
    email_employee = company.employees.find_or_initialize_by(email: "ops.analyst@acme.local")
    email_employee.assign_attributes(
      phone_e164: nil,
      display_name: "Nadia Email",
      department: "operations",
      participation_status: "invited",
      onboarding_step: "awaiting_name",
      invited_at: Time.current,
      invited_by_company_user: company_admin
    )
    email_employee.save!

    # Refresh counters/readiness from underlying data
    CompanyReadinessRefresher.call(company)

    ReviewerAssignment.find_or_create_by!(company: company, reviewer_user: reviewer, status: "active") do |a|
      a.assigned_by_platform_user = platform
      a.assigned_at = Time.current
    end

    snapshot = {
      "generated_at" => Time.current.iso8601,
      "company" => { "name" => company.display_name || company.name, "locale" => company.locale },
      "readiness" => {
        "score" => company.report_readiness_score,
        "breakdown" => company.report_readiness_breakdown
      },
      "participation" => {
        "invited" => company.employees.count,
        "completed" => company.employees.where(participation_status: "completed").count
      },
      "signals" => [],
      "patterns" => [],
      "recommendations" => []
    }

    # Internal report (in review) so platform sees reviewer readiness
    internal_report = company.reports.find_or_initialize_by(version: 1)
    internal_report.assign_attributes(
      status: "ready",
      visibility: "internal_only",
      review_workflow_status: "in_review",
      triggered_by_type: "CompanyUser",
      triggered_by_id: company_admin.id,
      generated_at: Time.current,
      report_snapshot: snapshot,
      content_type: "text/html",
      storage_key: nil
    )
    internal_report.save!

    review = ReportReview.find_or_initialize_by(report: internal_report, reviewer_user: reviewer)
    review.assign_attributes(
      company: company,
      status: "in_review",
      overall_note: "Overall direction is good; waiting for two clarifications.",
      ready_at: Time.current,
      ready_note: "Information looks sufficient from my side."
    )
    review.save!

    ReportSections::KEYS.each do |key|
      state = review.report_review_section_states.find_or_initialize_by(section_key: key)
      state.status = (key == "recommendations" ? "needs_info" : "approved")
      state.save!
    end

    ReportReviewComment.find_or_create_by!(
      report_review: review,
      reviewer_user: reviewer,
      section_key: "recommendations",
      body: "Please tighten recommendation ownership and sequencing."
    )

    # Seed reviewer follow-up threads so Reviewer portal has realistic inbox data.
    seeded_employees = company.employees.where(phone_e164: employee_rows.map { |r| r[:phone] }).order(:id).to_a
    followup_templates = [
      {
        body: "Please confirm who owns PO approvals above 10k and the usual turnaround time.",
        status: "awaiting_reply",
        reply: nil
      },
      {
        body: "Can you share where handoff details are currently tracked and who updates them?",
        status: "replied",
        reply: "We track this in a shared sheet. Ops coordinator updates it twice daily."
      },
      {
        body: "What is the biggest blocker stopping weekly reconciliation from finishing on time?",
        status: "sent",
        reply: nil
      }
    ]

    followup_templates.each_with_index do |template, idx|
      employee = seeded_employees[idx % seeded_employees.size]
      conversation = company.conversations.where(employee_id: employee.id).order(updated_at: :desc).first
      next unless conversation

      info_request = ReviewerInfoRequest.find_or_initialize_by(
        company: company,
        reviewer_user: reviewer,
        employee: employee,
        conversation: conversation,
        body: template[:body]
      )
      info_request.assign_attributes(
        report: internal_report,
        status: template[:status],
        sent_at: info_request.sent_at || (12.hours.ago + idx.hours),
        meta_message_id: info_request.meta_message_id || "demo-followup-#{employee.id}-#{idx}"
      )
      info_request.save!

      next unless template[:reply]

      inbound = Message.find_or_create_by!(external_id: "demo-followup-reply-#{employee.id}-#{idx}") do |m|
        m.conversation = conversation
        m.direction = "inbound"
        m.message_type = "text"
        m.body = template[:reply]
        m.processing_status = "ready"
        m.reviewer_followup = true
      end

      ReviewerInfoReply.find_or_create_by!(reviewer_info_request: info_request, message: inbound) do |reply|
        reply.body = template[:reply]
        reply.received_at = Time.current - (idx + 1).hours
      end
    end

    # Seed one failed audio attachment to demo reprocess flow in reviewer conversation details.
    failed_attachment_conversation = company.conversations.order(updated_at: :desc).first
    if failed_attachment_conversation
      failed_media_message = Message.find_or_create_by!(external_id: "demo-failed-media-#{failed_attachment_conversation.id}") do |m|
        m.conversation = failed_attachment_conversation
        m.direction = "inbound"
        m.message_type = "audio"
        m.body = nil
        m.processing_status = "failed"
        m.reviewer_followup = false
      end

      MediaAttachment.find_or_create_by!(message: failed_media_message) do |a|
        a.company = company
        a.employee = failed_attachment_conversation.employee
        a.conversation = failed_attachment_conversation
        a.attachment_type = "audio"
        a.status = "failed"
        a.processing_error = "transcription timeout"
      end
    end

    # Released report so company can download/share immediately
    released_report = company.reports.find_or_initialize_by(version: 2)
    released_report.assign_attributes(
      status: "ready",
      visibility: "shared_with_company",
      review_workflow_status: "platform_approved",
      triggered_by_type: "PlatformUser",
      triggered_by_id: platform.id,
      reviewed_by_platform_user: platform,
      reviewed_at: Time.current,
      generated_at: Time.current,
      report_snapshot: snapshot,
      content_type: "text/html",
      storage_key: nil
    )
    released_report.save!

    puts
    puts "Full demo seed complete."
    puts "Platform: admin@reqapp.local / password123"
    puts "Company:  admin@acme.local / password123"
    puts "Reviewer: reviewer@reqapp.local / password123"
    puts "Company:  #{company.display_name || company.name} (slug: #{company.slug})"
    puts "Employees seeded: #{company.employees.where(phone_e164: employee_rows.map { |r| r[:phone] }).count}"
    puts "Reports: v1 internal/in_review, v2 shared_with_company/platform_approved"
    puts "Reviewer followups: #{ReviewerInfoRequest.where(company_id: company.id, reviewer_user_id: reviewer.id).count}"
  end
end
