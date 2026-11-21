# frozen_string_literal: true

require "yaml"

module Voice
  # The live avatar's fixed lines (greeting, acknowledgements, "welcome back"...)
  # from the shared interviewer instructions file (agent/app/interviewer/
  # instructions.yaml, mounted read-only; path in INTERVIEWER_INSTRUCTIONS_PATH).
  # The agent validates the whole file; Rails re-checks only what it uses and falls
  # back to the built-in line for anything missing or unsuitable, so a bad edit
  # can never silence or derail the avatar.
  class InterviewerPhrases
    DEFAULT_ACKNOWLEDGEMENTS = ["Thank you.", "Okay, thanks.", "Got it, thank you.", "Thanks, one moment.",
                                "Right, thanks.", "Thanks for explaining."].freeze
    DEFAULT_PHRASES = {
      "greeting" => "Hi, thanks for joining. I'll ask you a few questions about your work. Just answer out loud, in your own words, and take your time.",
      "rephrase" => "Sorry, I couldn't record that properly. Could you say it again, maybe in slightly different words?",
      "still_working" => "Thanks. I'm still noting your last answer, one moment.",
      "resumed" => "Welcome back. Let's carry on."
    }.freeze
    DEFAULT_DISPLAY_NAME = "June"
    # Document 04 §4.6: employee content is peer-confidential; management sees
    # aggregated, de-identified findings, not individual transcripts.
    DEFAULT_CONSENT = [
      "This is a conversation about the work you actually do day to day. It usually takes 10 to 20 minutes.",
      "Your voice is processed by our speech and avatar providers so your answers can be transcribed; MJaDi keeps the text of your answers, not the recording.",
      "Your individual answers are confidential. Your organisation sees aggregated, de-identified findings, not your transcript.",
      "You can pause, switch to typing, or stop at any time."
    ].join(" ").freeze
    MAX_CONSENT = 1200
    MAX_LINE = 240
    MAX_ACK = 60
    UNSAFE = /password|api[ -]?key|credential|automat|redundan|headcount|manager (?:said|says|thinks)/i

    @cache = nil
    @mutex = Mutex.new

    class << self
      def acknowledgements
        acks = Array(section["acknowledgements"]).first(12).select { |a| ack?(a) }
        acks.presence || DEFAULT_ACKNOWLEDGEMENTS
      end

      def phrases
        DEFAULT_PHRASES.to_h { |key, default| [key, line?(section[key]) ? section[key].strip : default] }
      end

      def version
        loaded[:version]
      end

      # Shown on the avatar's web consent screen; its hash is the recorded consent version.
      def consent_text
        text = section["consent"]
        text.is_a?(String) && text.strip.present? && text.length <= MAX_CONSENT && !text.match?(UNSAFE) ? text.strip : DEFAULT_CONSENT
      end

      def consent_version
        "web-avatar-#{Digest::SHA256.hexdigest(consent_text)[0, 12]}"
      end

      def display_name
        name = section["display_name"]
        name.is_a?(String) && name.match?(/\A[\p{L} .'-]{1,40}\z/) ? name.strip : DEFAULT_DISPLAY_NAME
      end

      def path
        ENV["INTERVIEWER_INSTRUCTIONS_PATH"].presence ||
          Rails.root.join("..", "agent", "app", "interviewer", "instructions.yaml").to_s
      end

      def reset!
        @mutex.synchronize { @cache = nil }
      end

      private

      def section
        loaded[:avatar]
      end

      def ack?(text)
        text.is_a?(String) && text.strip.present? && text.length <= MAX_ACK && !text.include?("?") && !text.match?(UNSAFE)
      end

      def line?(text)
        text.is_a?(String) && text.strip.present? && text.length <= MAX_LINE && !text.match?(UNSAFE)
      end

      def loaded
        file = path
        mtime = File.mtime(file) rescue nil
        @mutex.synchronize do
          return @cache[:data] if @cache && @cache[:path] == file && @cache[:mtime] == mtime

          data = read(file, mtime)
          @cache = { path: file, mtime: mtime, data: data }
          data
        end
      end

      def read(file, mtime)
        return { avatar: {}, version: "builtin" } unless mtime

        raw = File.read(file)
        yaml = YAML.safe_load(raw) || {}
        avatar = yaml.is_a?(Hash) && yaml["avatar"].is_a?(Hash) ? yaml["avatar"] : {}
        { avatar: avatar, version: "#{yaml['version']}+#{Digest::SHA256.hexdigest(raw)[0, 12]}" }
      rescue Psych::Exception, SystemCallError => e
        Rails.logger.error("[Voice::InterviewerPhrases] unreadable #{file}: #{e.class.name} (using built-in lines)")
        { avatar: {}, version: "builtin" }
      end
    end
  end
end
