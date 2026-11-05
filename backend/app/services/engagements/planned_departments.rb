# frozen_string_literal: true

module Engagements
  # The departments taking part and how many people from each (Doc 07 P1–P2):
  # one shape wherever the plan is written — the onboarding form, the scope card
  # in the conversation with leadership, a Mjadi user's correction. A count is a
  # whole number, or UNKNOWN while nobody knows yet; a department appears once.
  module PlannedDepartments
    module_function

    def normalise(rows)
      seen = {}
      Array(rows).filter_map do |row|
        row = row.to_h.stringify_keys
        name = row["name"].to_s.squish.truncate(120)
        next if name.blank? || seen[name.downcase]

        seen[name.downcase] = true
        { "name" => name, "count" => count(row["count"]) }
      end
    end

    def count(value)
      text = value.to_s.strip
      text.match?(/\A\d+\z/) ? text.to_i : Companies::ProfileUpdater::UNKNOWN
    end

    # People in the plan whose department is no longer taking part: they keep
    # their department, and whoever changed the plan is told.
    def stranded_people(engagement, rows)
      names = rows.map { |r| r["name"].downcase }
      engagement.participants.planned.where.not(department: [nil, ""])
                .reject { |p| names.include?(p.department.downcase) }
    end
  end
end
