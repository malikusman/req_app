# frozen_string_literal: true

# The conversation with leadership as a participant sees it, behind either door:
# the key user's portal, or a manager's link. The including controller says who
# the participant is (key_participant).
#
# A participant sees their own conversation and nothing else: never what was
# captured from it, never the coverage or the planner's state, never anyone
# else's conversation (Doc 08 §27, Doc 14 §9.2).
module KeyPersonConversationEndpoints
  extend ActiveSupport::Concern

  MAX_TEXT = 4000
  MAX_AUDIO = 10.megabytes
  AUDIO_TYPES = %w[audio/webm audio/ogg audio/mpeg audio/mp4 audio/mp3 audio/wav audio/x-wav audio/m4a audio/x-m4a
                   audio/aac video/webm].freeze

  # Doc 14 §5: transcribed; what it's for; not shown to colleagues; pause, skip
  # or stop; how long it's kept.
  CONSENT_TEXT = {
    "en" => [
      "This conversation is written down as a transcript. Voice notes are turned into text and not kept.",
      "It's used to understand the business, so Mjadi knows where to look and how to help.",
      "What you say isn't shown to colleagues, including other managers. Findings describe work, never people.",
      "You can pause, skip a question or stop at any time.",
      "The transcript is kept while Mjadi works with your company, under the confidentiality terms already agreed."
    ],
    "ar" => [
      "يُدوَّن هذا الحديث نصاً. تُحوَّل الرسائل الصوتية إلى نص ولا يُحتفظ بها.",
      "يُستخدم لفهم أعمال الشركة، حتى تعرف Mjadi أين تنظر وكيف تساعد.",
      "لا يُعرض ما تقوله على زملائك، بمن فيهم المدراء الآخرون. تصف النتائج العمل، لا الأشخاص.",
      "يمكنك التوقف مؤقتاً، أو تخطي سؤال، أو التوقف نهائياً في أي وقت.",
      "يُحتفظ بالنص طوال مدة عمل Mjadi مع شركتك، وفق شروط السرية المتفق عليها."
    ]
  }.freeze

  included do
    rescue_from KeyPerson::Conversation::NotAvailable do
      render json: { error: "The conversation isn't available right now. The Mjadi team will be in touch." },
             status: :service_unavailable
    end
    rescue_from KeyPerson::Turn::Closed do
      render json: { error: "This conversation has finished." }, status: :conflict
    end
    rescue_from KeyPerson::Turn::NotStarted do
      render json: { error: "Please read and accept the note first." }, status: :conflict
    end
  end

  def show
    render json: conversation_json
  end

  def consent
    conversation.start!
    render json: conversation_json
  end

  def message
    text = params[:text].to_s.strip
    return render json: { errors: ["Write something first."] }, status: :unprocessable_entity if text.blank?
    return render json: { errors: ["That's too long for one message."] }, status: :unprocessable_entity if text.size > MAX_TEXT

    answer!(text, "TEXT")
  end

  # A voice note is transcribed and answered like typing (Doc 14 §7). The audio
  # itself isn't kept.
  def voice_note
    audio = params[:audio]
    unless audio.respond_to?(:tempfile) && AUDIO_TYPES.include?(audio.content_type.to_s.split(";").first) &&
           audio.size <= MAX_AUDIO
      return render json: { errors: ["That recording couldn't be used. Try again, or type your answer."] },
                    status: :unprocessable_entity
    end

    client = Openai::Client.new
    text = client.configured? ? client.transcribe_audio(file_path: audio.tempfile.path).to_s.strip : ""
    return unheard if text.blank?

    answer!(text, "VOICE_NOTE")
  rescue Openai::Client::Error
    unheard
  end

  def pause
    KeyPerson::Turn.new(started_session!).pause!
    render json: conversation_json
  end

  # An upload, now or later — after the conversation has ended too (Doc 14 §12).
  def upload
    KeyPerson::Documents.new(started_session!)
                        .upload!(params[:file], request_id: params[:document_request_id],
                                                uploaded_by: key_participant.company_user)
    render json: conversation_json, status: :created
  rescue ArgumentError => e
    render json: { errors: [e.message] }, status: :unprocessable_entity
  end

  def resume
    conversation.resume!
    render json: conversation_json
  end

  private

  def conversation
    @conversation ||= KeyPerson::Conversation.new(key_participant)
  end

  def unheard
    render json: { errors: ["We couldn't make out that voice note. Could you try again, or type it?"] },
           status: :unprocessable_entity
  end

  def started_session!
    conversation.session || raise(KeyPerson::Turn::NotStarted)
  end

  def answer!(text, input_mode)
    KeyPerson::Turn.new(started_session!).answer!(text: text, client_message_id: params[:client_message_id],
                                                  input_mode: input_mode)
    render json: conversation_json
  end

  def conversation_json
    participant = key_participant
    session = conversation.session
    language = session&.language || (participant.preferred_language.to_s.start_with?("ar") ? "ar" : "en")
    {
      available: KeyPerson::Conversation.available?(key_participant.company),
      participant: {
        name: participant.name, role_title: participant.role_title, key_user: participant.key_user?,
        participation_status: participant.participation_status, consented: participant.consent_recorded_at.present?
      },
      consent: { version: KeyPerson::Conversation::CONSENT_VERSION, points: CONSENT_TEXT.fetch(language) },
      session: session && session_json(session)
    }.merge(extra_json(session))
  end

  # What only one door adds (the key user's scope card).
  def extra_json(_session) = {}

  def session_json(session)
    planner = KeyPerson::Planner.new(snapshot: session.state_snapshot, persona: session.participant.persona)
    instruction = planner.instruction || {}
    {
      id: session.id, state: session.state, language: session.language, finished: session.finished?,
      needs_resume: conversation.needs_resume?(session), progress: session.finished? ? "done" : planner.progress,
      mode: instruction["mode"],
      themes: session.state == "PRIORITY_CONFIRMATION" ? Array(instruction["themes"]) : [],
      document_requests: KeyPerson::Documents.new(session).json,
      turns: session.history.map do |turn|
        { index: turn.turn_index, from: turn.assistant? ? "assistant" : "participant", text: turn.text,
          input_mode: turn.input_mode, at: turn.created_at.iso8601 }
      end
    }
  end
end
