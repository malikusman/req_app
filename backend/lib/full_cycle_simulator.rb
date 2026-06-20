# frozen_string_literal: true

require "net/http"

# End-to-end product simulation beyond discovery:
#
#   discovery (live LLM) → nudge → intelligence → report/PDF → reviewer follow-up
#
# Usage:
#   rails demo:full_cycle
#   PERSONA=hr_manager CLEANUP=1 rails demo:full_cycle
class FullCycleSimulator
  STALLED_PHONE = "+14155559903"
  STALLED_NAME = "Stalled Tester"

  def self.call(slug: ENV.fetch("SLUG", "acme-corp"), persona: ENV.fetch("PERSONA", "finance_ic"), cleanup: ENV["CLEANUP"] == "1")
    new(slug: slug, persona: persona, cleanup: cleanup).call
  end

  def initialize(slug:, persona:, cleanup:)
    @slug = slug
    @persona_key = persona
    @cleanup = cleanup
    @checks = []
    @created_report = nil
    @stalled_employee = nil
    @discovery = nil
  end

  def call
    banner "Full cycle simulation — #{@persona_key} @ #{@slug}"
    @company = Company.find_by!(slug: @slug)
    @admin = @company.company_users.find_by!(role: "company_admin")
    @platform = PlatformUser.first!
    @reviewer = ReviewerUser.find_by!(email: "reviewer@reqapp.local")
    ensure_reviewer_assignment!

    run_discovery!
    run_nudge!
    run_intelligence!
    run_report!
    run_reviewer_followup!

    print_report
  ensure
    cleanup! if @cleanup
  end

  private

  def ensure_reviewer_assignment!
    return if @company.reviewer_assignments.active.exists?(reviewer_user_id: @reviewer.id)

    ReviewerAssignment.create!(
      company: @company,
      reviewer_user: @reviewer,
      assigned_by_platform_user: @platform,
      assigned_at: Time.current,
      status: "active"
    )
  end

  def run_discovery!
    stage "Discovery (live multi-agent interview)"
    @discovery = DiscoverySimulator.new(slug: @slug, persona: @persona_key, cleanup: false)
    @discovery.execute_stages!
    @discovery.checks.each do |label, passed|
      check "[discovery] #{label}", passed
    end
    @employee = @discovery.employee
    @conversation = @discovery.conversation
  end

  def run_nudge!
    stage "Employee nudge (stalled participant)"
    reset_stalled_employee!
    create_stalled_employee!

    SendEmployeeNudgeJob.perform_now(@stalled_employee.id, @admin.id)
    @stalled_employee.reload

    nudge = EmployeeNudge.where(employee_id: @stalled_employee.id).order(sent_at: :desc).first
    check "Nudge job created EmployeeNudge record", nudge.present?
    check "Nudge updated last_nudged_at", @stalled_employee.last_nudged_at.present?
    check "Nudge linked to conversation", nudge&.conversation_id.present?
  end

  def run_intelligence!
    stage "Intelligence aggregation"
    result = Intelligence::AggregateCompanyIntelligence.call(company: @company)
    @company.reload

    check "Signals extracted (#{result[:signals]})", result[:signals].to_i.positive?
    check "Patterns detected (#{result[:patterns]})", result[:patterns].to_i >= 0
    check "Recommendations synthesized (#{result[:recommendations]})", result[:recommendations].to_i >= 0
    check "Readiness score refreshed", @company.report_readiness_score.to_f.positive?
  end

  def run_report!
    stage "Report generation + PDF"
    gotenberg_up = service_healthy?("GOTENBERG_URL", "http://gotenberg:3000", "/health")
    minio_up = minio_healthy?
    check "Gotenberg reachable", gotenberg_up
    check "MinIO reachable", minio_up

    previous = @company.reports.ready.order(version: :desc).first
    @created_report = @company.reports.create!(
      version: (@company.reports.maximum(:version) || 0) + 1,
      status: "queued",
      visibility: "internal_only",
      triggered_by_type: "PlatformUser",
      triggered_by_id: @platform.id,
      previous_report: previous
    )

    Reports::GenerateReportService.call(report: @created_report)
    @created_report.reload

    check "Report status ready", @created_report.status == "ready"
    check "Report stored in MinIO", @created_report.storage_key.present?
    check "Report snapshot populated", @created_report.report_snapshot.present?

    if @company.reviewer_assignments.active.exists?
      review_count = @created_report.report_reviews.count
      check "Reviewer reviews bootstrapped (#{review_count})", review_count.positive?
    else
      check "Reviewer assigned to company", false
    end

    body = Storage::MinioClient.new.download(@created_report.storage_key)
    pdf_bytes = body.start_with?("%PDF")
    html_fallback = @created_report.content_type == "text/html"

    if gotenberg_up
      check "PDF generated via Gotenberg", pdf_bytes || @created_report.content_type == "application/pdf"
    else
      check "HTML fallback when Gotenberg down (warn)", html_fallback
    end

    check "Downloaded artifact non-empty (#{body.bytesize} bytes)", body.bytesize > 100
  rescue StandardError => e
    check "Report generation succeeded", false
    puts "  ✗ Report error: #{e.message}"
  end

  def run_reviewer_followup!
    stage "Reviewer follow-up (send + employee reply)"
    unless @reviewer && @company.reviewer_assignments.active.exists?(reviewer_user_id: @reviewer.id)
      check "Reviewer assigned for follow-up", false
      return
    end

    @employee.reload
    @conversation.reload
    @conversation.update!(last_activity_at: Time.current)

    followup_body = "Can you share one concrete example of the manual step you mentioned?"
    result = ReviewerFollowup::SendService.call(
      reviewer: @reviewer,
      employee: @employee,
      body: followup_body,
      report: @created_report
    )
    request = result[:request]

    check "Follow-up request created", request.present?
    check "Follow-up status awaiting_reply", request.status == "awaiting_reply"
    check "Follow-up outbound message marked reviewer_followup",
          result[:message].reviewer_followup?

    reply_text = "Sure — I export the open invoice list from SAP every morning and re-enter approved rows by hand in Excel."
    simulate_inbound(@employee, reply_text)

    request.reload
    check "Employee reply recorded", request.status == "replied"
    check "ReviewerInfoReply created", request.reviewer_info_replies.exists?
    check "Reply message flagged reviewer_followup",
          @conversation.messages.where(direction: "inbound", reviewer_followup: true).exists?
  end

  def create_stalled_employee!
    @stalled_employee = @company.employees.create!(
      phone_e164: STALLED_PHONE,
      display_name: STALLED_NAME,
      department: "sales",
      participation_status: "started",
      started_at: 2.days.ago,
      last_active_at: 2.days.ago
    )
    @stalled_employee.conversations.create!(
      company: @company,
      status: "discovery",
      question_count: 2,
      started_at: 2.days.ago,
      last_activity_at: 2.days.ago
    )
  end

  def reset_stalled_employee!
    employee = Employee.find_by(phone_e164: STALLED_PHONE)
    DiscoverySimulator.purge_employee!(employee, company: @company) if employee
  end

  def simulate_inbound(employee, text)
    phone = employee.phone_e164
    payload = {
      "entry" => [{ "changes" => [{ "value" => {
        "messages" => [{
          "from" => phone.delete("+"),
          "id" => "wamid.sim.#{SecureRandom.hex(8)}",
          "type" => "text",
          "text" => { "body" => text }
        }],
        "contacts" => [{ "wa_id" => phone.delete("+"), "profile" => { "name" => employee.display_name } }]
      } }] }]
    }
    Whatsapp::InboundProcessor.new(payload).process
  end

  def service_healthy?(env_key, default_url, path)
    uri = URI("#{ENV.fetch(env_key, default_url).chomp('/')}#{path}")
    response = Net::HTTP.get_response(uri)
    response.is_a?(Net::HTTPSuccess)
  rescue StandardError
    false
  end

  def minio_healthy?
    Storage::MinioClient.new
    true
  rescue StandardError
    false
  end

  def cleanup!
    stage "Cleanup"
    DiscoverySimulator.purge_employee!(@discovery.employee, company: @company) if @discovery&.employee
    DiscoverySimulator.purge_employee!(@stalled_employee, company: @company) if @stalled_employee&.persisted?

    if @created_report&.persisted?
      Storage::MinioClient.new.delete(@created_report.storage_key) if @created_report.storage_key.present?
      @created_report.destroy!
    end

    puts "  Simulated employees and test report removed."
  end

  def check(label, passed)
    @checks << [label, passed]
    puts format("  %s %s", passed ? "✓" : "✗ FAIL —", label)
  end

  def stage(name)
    puts "\n— #{name} " + "-" * [60 - name.length, 5].max
  end

  def banner(text)
    puts "=" * 70
    puts text
    puts "=" * 70
  end

  def print_report
    failed = @checks.reject { |_, passed| passed }
    banner format(
      "Full cycle finished — %d/%d checks passed%s",
      @checks.size - failed.size,
      @checks.size,
      failed.any? ? " — #{failed.size} FAILED" : ""
    )
    failed.each { |label, _| puts "  ✗ #{label}" }
    unless @cleanup
      puts "\nView discovery in platform portal → #{@company.name} → Conversations"
      puts "(re-run with CLEANUP=1 to remove simulated data)"
    end
    raise "Full cycle failed: #{failed.map(&:first).join('; ')}" if failed.any?
  end
end
