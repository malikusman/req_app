# frozen_string_literal: true

module ReportSections
  # The sections a consultant judges before a report can be approved. Readiness and
  # participation were replaced by Scope & coverage: they measured our delivery,
  # not the client's business. Findings by role is the section the report is built
  # around, so it is judged second, after the summary it supports.
  DEFINITIONS = [
    { "key" => "executive_summary", "title" => "Executive summary" },
    { "key" => "role_findings", "title" => "Findings by role" },
    { "key" => "delta", "title" => "Changes since last report" },
    { "key" => "signals", "title" => "Top pain points" },
    { "key" => "patterns", "title" => "Cross-team patterns" },
    { "key" => "recommendations", "title" => "Recommendations" },
    { "key" => "coverage", "title" => "Scope & coverage" }
  ].freeze

  KEYS = DEFINITIONS.map { |s| s["key"] }.freeze
end
