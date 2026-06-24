# frozen_string_literal: true

module Discovery
  # Builds the synthetic employee kickoff passed to the agent on proactive discovery start.
  class KickoffMessage
    def self.build(employee:)
      new(employee: employee).build
    end

    def initialize(employee:)
      @employee = employee
    end

    def build
      profile = @employee.profile_card
      if @employee.profile_complete?
        profile_summary(profile)
      else
        minimal_intro(profile)
      end
    end

    private

    def profile_summary(profile)
      parts = ["I'm #{profile['name']}, a #{profile['role_title']} in #{profile['department']}."]
      parts << profile["responsibilities"] if profile["responsibilities"].present?
      tools = Array(profile["primary_tools"])
      parts << "I mainly use #{tools.join(', ')}." if tools.any?
      parts.join(" ")
    end

    def minimal_intro(profile)
      name = profile["name"].presence || "the employee"
      role = profile["role_title"].presence
      department = profile["department"].presence
      department = nil if department == "default"

      if role && department
        "I'm #{name}, #{role} in #{department}. I'm ready to walk through how I work day to day."
      elsif role
        "I'm #{name}, #{role}. I'm ready to walk through how I work day to day."
      else
        "I'm #{name}. I'm ready to walk through how I work day to day."
      end
    end
  end
end
