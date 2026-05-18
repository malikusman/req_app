# frozen_string_literal: true

module ReportSections
  DEFINITIONS = [
    { "key" => "executive_summary", "title" => "Executive summary" },
    { "key" => "readiness", "title" => "Readiness" },
    { "key" => "participation", "title" => "Participation" },
    { "key" => "delta", "title" => "Changes since last report" },
    { "key" => "signals", "title" => "Top pain points" },
    { "key" => "patterns", "title" => "Cross-team patterns" },
    { "key" => "recommendations", "title" => "Recommendations" }
  ].freeze

  KEYS = DEFINITIONS.map { |s| s["key"] }.freeze
end
