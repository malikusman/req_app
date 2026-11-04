# frozen_string_literal: true

module Llm
  # The one switch for every model step behind a report: the narrative, the
  # priorities, and the drafted causes, directions and links. Off only when
  # explicitly disabled. Local Gemma testing works by pointing OPENAI_BASE_URL at
  # the local endpoint and setting a dummy OPENAI_API_KEY.
  module ReportNarrative
    module_function

    def enabled?
      ENV.fetch("AI_REPORT_NARRATIVE", "true").to_s.downcase != "false"
    end
  end
end
