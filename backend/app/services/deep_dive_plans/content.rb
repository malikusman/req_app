# frozen_string_literal: true

module DeepDivePlans
  class Content
    def initialize(context)
      @source_ids = context.fetch("sources").pluck("id")
      @clarification_ids = context.fetch("open_clarifications").pluck("id")
    end

    def validate(data, generated: false)
      raise Invalid, "Provide a structured plan." unless data.is_a?(Hash)

      minutes = data["duration_minutes"]
      raise Invalid, "Duration must be a whole number between 5 and 120 minutes." unless minutes.is_a?(Integer) && minutes.between?(5, 120)

      sections = list(data["sections"], "Sections", 12, minimum: 1).map do |section|
        raise Invalid, "Provide a title and questions for each section." unless section.is_a?(Hash)

        { "title" => self.class.text(section["title"], "Section title", 120),
          "questions" => list(section["questions"], "Questions", 20, minimum: 1).map { |item| question(item) } }
      end
      if generated && (@clarification_ids - sections.flat_map { |section| section["questions"].flat_map { |item| item["clarification_ids"] } }).any?
        raise Invalid, "Generated questions must address every linked open clarification."
      end

      {
        "objective" => self.class.text(data["objective"], "Objective", 2_000),
        "scope" => self.class.text(data["scope"], "Scope", 2_000),
        "instructions" => self.class.text(data["instructions"], "Instructions", 2_000),
        "duration_minutes" => minutes, "sections" => sections,
        "focus_areas" => texts(data["focus_areas"], "Focus areas"),
        "document_requests" => texts(data["document_requests"], "Document requests")
      }
    end

    def self.text(value, label, max)
      raise Invalid, "#{label} is required and must be at most #{max} characters." unless value.is_a?(String) && value.strip.length.between?(1, max)

      value.strip
    end

    private

    def question(item)
      raise Invalid, "Provide question text and valid references." unless item.is_a?(Hash)

      { "text" => self.class.text(item["text"], "Question", 700),
        "source_ids" => references(item["source_ids"], @source_ids),
        "clarification_ids" => references(item["clarification_ids"], @clarification_ids) }
    end

    def references(value, allowed)
      ids = list(value || [], "References", allowed.length)
      raise Invalid, "References must belong to this plan." unless ids.all? { |id| id.is_a?(Integer) && allowed.include?(id) }

      ids.uniq
    end

    def texts(values, label)
      list(values, label, 20).map { |value| self.class.text(value, label, 500) }
    end

    def list(value, label, max, minimum: 0)
      raise Invalid, "#{label} must contain #{minimum}–#{max} entries." unless value.is_a?(Array) && value.size.between?(minimum, max)

      value
    end
  end
end
