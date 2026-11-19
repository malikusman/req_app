# frozen_string_literal: true

module Voice
  # In-process cache of synthesised audio for the avatar's FIXED phrases only
  # (acknowledgements, greeting, "welcome back"...). These are spoken on every
  # turn and contain no employee data, so after the first synthesis they play at
  # once instead of waiting ~1 s for OpenAI. Interview questions are never cached.
  class PhraseAudioCache
    MAX_ENTRIES = 32
    MAX_BYTES = 2_000_000 # per phrase (~40 s of 24 kHz PCM16)
    SLICE = 16_384

    @store = {}
    @mutex = Mutex.new

    class << self
      def key(text)
        Digest::SHA256.hexdigest([text, ENV.fetch("OPENAI_TTS_MODEL", "gpt-4o-mini-tts"), ENV.fetch("OPENAI_TTS_VOICE", "alloy")].join("\u0000"))
      end

      def read(text)
        @mutex.synchronize { @store[key(text)] }
      end

      def write(text, audio)
        return if audio.bytesize.zero? || audio.bytesize > MAX_BYTES

        @mutex.synchronize do
          @store.shift if @store.size >= MAX_ENTRIES && !@store.key?(key(text))
          @store[key(text)] = audio.dup.freeze
        end
      end

      def clear
        @mutex.synchronize { @store.clear }
      end

      # Yields cached audio in slices, like a live stream.
      def each_slice(audio)
        0.step(audio.bytesize - 1, SLICE) { |offset| yield audio.byteslice(offset, SLICE) }
      end
    end
  end
end
