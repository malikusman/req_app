#!/usr/bin/env ruby
# frozen_string_literal: true

# Purge prior WhatsApp test data for a phone number and invite fresh to a company.
#
# Usage:
#   rails runner lib/manual_test/provision_whatsapp_user.rb
#   PHONE=+971526187620 COMPANY=acme-corp DEPARTMENT=finance rails runner lib/manual_test/provision_whatsapp_user.rb
#   SEND_WHATSAPP=false rails runner lib/manual_test/provision_whatsapp_user.rb

require_relative "../discovery_simulator"

phone = PhoneNormalizer.call(ENV.fetch("PHONE", "+971526187620"))
slug = ENV.fetch("COMPANY", "acme-corp")
department = ENV.fetch("DEPARTMENT", "finance")
display_name = ENV["DISPLAY_NAME"]
send_whatsapp = ENV.fetch("SEND_WHATSAPP", "true") == "true"

company = Company.find_by!(slug: slug)
admin = company.company_users.find_by(role: "company_admin")
raise "No company_admin for #{slug}" unless admin

purged = []
Employee.where(phone_e164: phone).find_each do |employee|
  DiscoverySimulator.purge_employee!(employee, company: employee.company)
  purged << "#{employee.id}@#{employee.company.slug}"
end

result = InviteEmployeeService.call(
  company: company,
  phone_e164: phone,
  display_name: display_name,
  department: department,
  invited_by: admin,
  send_whatsapp: send_whatsapp
)

puts "=== WhatsApp test user provisioned ==="
puts "Phone:       #{phone}"
puts "Company:     #{company.name} (#{slug})"
puts "Purged:      #{purged.empty? ? 'none' : purged.join(', ')}"
puts "Employee ID: #{result[:employee].id}"
puts "Access code: #{result[:access_code]}"
puts "WhatsApp:    #{send_whatsapp ? 'invite queued' : 'skipped (SEND_WHATSAPP=false)'}"
