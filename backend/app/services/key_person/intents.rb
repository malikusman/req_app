# frozen_string_literal: true

module KeyPerson
  # The question-intent library (Doc 08 §9.3, §33). The platform picks the area
  # and passes its intent to P02, which writes the words. When P02 fails twice, or
  # its reply breaks the rules, the platform asks the fallback question here
  # instead (P02 §11) — the "good question" column of §9.3, in English and
  # Modern Standard Arabic.
  module Intents
    AREAS = {
      "STRATEGIC_OBJECTIVES" => {
        intent: "what they want the business or their area to achieve over the next 12 to 24 months",
        en: "Where do you want the business to be in two years that it isn't today?",
        ar: "ما الذي تريد أن تصل إليه الشركة خلال العامين القادمين ولم تصل إليه بعد؟"
      },
      "GROWTH_PRIORITIES" => {
        intent: "what growth means for them — customers, markets, products, margin, service or scale",
        en: "Is growth limited more by finding customers, or by handling the ones you have?",
        ar: "هل يحدّ من النمو أكثرَ إيجادُ عملاء جدد، أم خدمةُ العملاء الحاليين؟"
      },
      "CONCERNS" => {
        intent: "what takes up their attention or causes frustration, delay, errors or risk",
        en: "What's the thing you find yourself chasing most often?",
        ar: "ما الأمر الذي تجد نفسك تلاحقه أكثر من غيره؟"
      },
      "BOTTLENECKS" => {
        intent: "where work slows down, piles up or is hard to manage",
        en: "Where does work tend to pile up waiting for someone?",
        ar: "أين يتراكم العمل عادةً بانتظار أحدٍ ما؟"
      },
      "STAKEHOLDER_EXPERIENCE" => {
        intent: "where customers, suppliers or staff feel friction",
        en: "What do your best customers complain about?",
        ar: "ما الذي يشتكي منه أفضل عملائكم؟"
      },
      "PEOPLE_WORKLOAD" => {
        intent: "overloaded teams, dependence on particular people, capacity",
        en: "Is there anyone the business would really struggle without for a month?",
        ar: "هل هناك شخص ستواجه الشركة صعوبة حقيقية لو غاب شهراً؟"
      },
      "SYSTEMS" => {
        intent: "which systems matter and where they fall short, without assuming what they can do",
        en: "Which system does your team work around most?",
        ar: "ما النظام الذي يضطر فريقك إلى الالتفاف عليه أكثر من غيره؟"
      },
      "REPORTING" => {
        intent: "information they wish they had sooner, more accurately or differently",
        en: "What number do you wish you could see every morning but can't?",
        ar: "ما الرقم الذي تتمنى أن تراه كل صباح ولا تستطيع؟"
      },
      "DECISIONS_APPROVALS" => {
        intent: "where approvals, ownership or escalation hold work up",
        en: "What has to come to you personally that you wish didn't?",
        ar: "ما الذي يجب أن يمرّ عليك شخصياً وتتمنى لو لم يكن كذلك؟"
      },
      "DATA_DOCUMENTS" => {
        intent: "duplicate entry, hard-to-find information, document handling",
        en: "Where does the same information get typed in more than once?",
        ar: "أين تُدخَل المعلومات نفسها أكثر من مرة؟"
      },
      "PLANNED_INITIATIVES" => {
        intent: "changes already planned — new systems, restructures, hiring, outsourcing, policy changes",
        en: "Is anything big already planned, like a new system or a restructure?",
        ar: "هل هناك أمر كبير مخطط له بالفعل، كنظام جديد أو إعادة هيكلة؟"
      },
      "CONSTRAINTS" => {
        intent: "timing, security, regulatory or cultural limits, and anything not to disturb",
        en: "Is there anything we shouldn't disturb, or any timing we should work around?",
        ar: "هل هناك ما ينبغي ألا نمسّه، أو توقيت علينا مراعاته؟"
      },
      "SUCCESS_DEFINITION" => {
        intent: "what would make this engagement worthwhile to them",
        en: "At the end of this, what would make you say it was worth it?",
        ar: "في نهاية هذا العمل، ما الذي سيجعلك تقول إنه كان يستحق؟"
      },
      "PRIORITY_AREAS" => {
        intent: "where they most want Mjadi to look first",
        en: "If we could only look at one area properly, which would you choose?",
        ar: "لو استطعنا أن ننظر في مجال واحد فقط بعناية، فأيّها تختار؟"
      },
      "AMBITION" => {
        intent: "what they wish the business could do but can't today, as an ambition rather than a technology",
        en: "What would you do if you had the time and the means?",
        ar: "ما الذي كنت ستفعله لو توفّر لك الوقت والإمكانات؟"
      },
      "RELEASED_TIME" => {
        intent: "if key teams had more time, where they would want it spent",
        en: "If your team had a few hours a week back, where would you want them spent?",
        ar: "لو استعاد فريقك بضع ساعات في الأسبوع، فأين تريد أن تُصرف؟"
      }
    }.freeze

    # Safe lines for the turns that aren't about one area.
    LINES = {
      "OPENING" => {
        en: "Thank you for making the time. I've been through what your team shared, so I won't ask you about " \
            "the basics. What I'd like to understand is where you're taking the business and what's getting in " \
            "the way. It usually takes about fifteen to twenty minutes, and you can pause whenever you need. " \
            "Shall we start?",
        ar: "شكراً لك على وقتك. اطّلعتُ على ما شاركه فريقكم، فلن أسألك عن الأساسيات. ما أودّ فهمه هو الاتجاه " \
            "الذي تريد أن تأخذ إليه الشركة، وما الذي يعيق ذلك. يستغرق الحديث عادةً نحو خمس عشرة إلى عشرين " \
            "دقيقة، ويمكنك التوقف متى شئت. هل نبدأ؟"
      },
      "PRIORITY_READ_BACK" => {
        en: "Before we finish, I'd like to check I've understood what matters most to you. Of everything we've " \
            "talked about, which matters most, or what have I missed?",
        ar: "قبل أن ننهي، أودّ أن أتأكد من أنني فهمت ما يهمك أكثر. من بين كل ما تحدثنا عنه، ما الأهم بالنسبة " \
            "إليك، أو ما الذي فاتني؟"
      },
      "SCOPE_AND_PARTICIPANTS" => {
        en: "When we speak with your team, who really knows how the day-to-day work runs?",
        ar: "عندما نتحدث مع فريقك، من الذي يعرف حقاً كيف يسير العمل اليومي؟"
      },
      "DOCUMENT_REQUEST" => {
        en: "You mentioned a few documents along the way. Could you share any of them? It's optional, and you " \
            "can add them later.",
        ar: "ذكرتَ بعض المستندات أثناء حديثنا. هل يمكنك مشاركة أيٍّ منها؟ الأمر اختياري، ويمكنك إضافتها لاحقاً."
      },
      "ANYTHING_ELSE" => {
        en: "Is there anything you expected us to talk about that we haven't?",
        ar: "هل هناك ما توقعتَ أن نتحدث عنه ولم نفعل؟"
      },
      "CLOSING" => {
        en: "Thank you, that's been really helpful. Next, we'll speak with the people you suggested, and the " \
            "team will be in touch with you.",
        ar: "شكراً لك، كان هذا مفيداً جداً. سنتحدث بعد ذلك مع الأشخاص الذين اقترحتهم، وسيتواصل معك الفريق."
      },
      "HANDLE_ASIDE" => {
        en: "Good question — the team will follow up with you on that separately.",
        ar: "سؤال جيد، وسيتابع الفريق معك بشأنه بشكل منفصل."
      },
      "CLARIFY" => {
        en: "Just so I have it right, could you say a little more about that?",
        ar: "حتى أتأكد من أنني فهمت بشكل صحيح، هل يمكنك أن توضح ذلك قليلاً؟"
      },
      "RESUME" => {
        en: "Welcome back.",
        ar: "أهلاً بعودتك."
      },
      "PAUSE" => {
        en: "Of course. Everything is saved, and we'll pick up from here whenever you're ready.",
        ar: "بالتأكيد. كل شيء محفوظ، وسنكمل من هنا متى كنت مستعداً."
      }
    }.freeze

    module_function

    def intent(area) = AREAS.fetch(area)[:intent]

    def question(area, language) = AREAS.fetch(area)[lang(language)]

    def line(mode, language) = LINES.fetch(mode)[lang(language)]

    def lang(language) = language.to_s.start_with?("ar") ? :ar : :en
  end
end
