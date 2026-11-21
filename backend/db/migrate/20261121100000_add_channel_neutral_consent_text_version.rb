# frozen_string_literal: true

# The consent message said "via WhatsApp", and web interviews send the same text,
# so employees on the web were told they were on WhatsApp. This version names no
# channel and adds Arabic, which fell back to English before. Keywords stay as
# they were; Arabic adds its own "yes". Opt-out still listens for STOP, so the
# Arabic text asks for it too.
class AddChannelNeutralConsentTextVersion < ActiveRecord::Migration[7.1]
  VERSION = "2026-11-21"
  PREVIOUS = "2026-06-20"

  class ConsentTextRecord < ActiveRecord::Base
    self.table_name = "consent_text_versions"
  end

  def up
    ConsentTextRecord.where(active: true).update_all(active: false)
    TEXTS.each do |locale, attrs|
      record = ConsentTextRecord.find_or_initialize_by(version: VERSION, locale: locale)
      record.update!(body: attrs[:body], confirmation_keywords: attrs[:keywords], active: true)
    end
  end

  def down
    ConsentTextRecord.where(version: VERSION).delete_all
    ConsentTextRecord.where(version: PREVIOUS).update_all(active: true)
  end

  TEXTS = {
    "en" => {
      keywords: ["YES", "I AGREE"],
      body: <<~TEXT.squish
        Before we begin: I'll ask you some questions about the work you do day to day. It usually takes
        10 to 20 minutes. You can type, or send voice notes, screenshots or PDFs if that's easier. Voice notes
        and files may be transcribed or read by AI to understand your work. Your individual answers are
        confidential: your organisation sees combined findings, not your conversation or your files.
        Reply YES to continue or STOP to opt out.
      TEXT
    },
    "ar" => {
      keywords: ["نعم", "موافق", "YES"],
      body: <<~TEXT.squish
        قبل أن نبدأ: سأطرح عليك بعض الأسئلة عن عملك اليومي. يستغرق ذلك عادةً من 10 إلى 20 دقيقة.
        يمكنك الكتابة، أو إرسال رسائل صوتية أو لقطات شاشة أو ملفات PDF إذا كان ذلك أسهل.
        قد يُفرَّغ الصوت والملفات أو يقرؤها الذكاء الاصطناعي لفهم عملك. إجاباتك الفردية سرية:
        ترى مؤسستك النتائج المجمّعة فقط، وليس محادثتك أو ملفاتك.
        أرسل "نعم" للمتابعة أو STOP لإلغاء المشاركة.
      TEXT
    },
    "es" => {
      keywords: ["SI", "YES"],
      body: <<~TEXT.squish
        Antes de comenzar: te haré algunas preguntas sobre tu trabajo del día a día. Suele llevar
        de 10 a 20 minutos. Puedes escribir, o enviar notas de voz, capturas o PDFs si te resulta más fácil.
        Las notas de voz y los archivos pueden transcribirse o leerse con IA para entender tu trabajo.
        Tus respuestas individuales son confidenciales: tu organización ve resultados combinados, no tu
        conversación ni tus archivos. Responde SI para continuar o STOP para cancelar.
      TEXT
    }
  }.freeze
end
