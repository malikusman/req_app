# frozen_string_literal: true

namespace :discovery do
  desc "Run one discovery turn for employee PHONE=+1... TEXT='answer'"
  task turn: :environment do
    phone = ENV.fetch("PHONE")
    text = ENV.fetch("TEXT")
    employee = Employee.find_by!(phone_e164: phone)
    conversation = employee.conversations.where(status: %w[discovery onboarding]).order(created_at: :desc).first
    conversation ||= employee.conversations.create!(
      company: employee.company,
      status: "discovery",
      started_at: Time.current,
      last_activity_at: Time.current
    )
    employee.update!(onboarding_step: "verified", participation_status: "started") if employee.onboarding_step != "verified"

    result = Discovery::ProcessTurnService.call(
      conversation: conversation,
      employee: employee,
      user_message: text,
      defer_on_failure: false
    )

    puts "Assistant: #{result['assistant_message']}"
    puts "Completed: #{result['completed']}"
    puts "Questions: #{conversation.reload.question_count}"
  end
end
