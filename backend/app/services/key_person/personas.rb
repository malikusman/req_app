# frozen_string_literal: true

module KeyPerson
  # Who the conversation is with (Doc 08 §3). A first guess from the person's job
  # title, which the opening confirms and a consultant may correct. The persona
  # sets which coverage column weights the conversation (§8.2): broad for a CEO,
  # cross-functional for a GM or COO, operational for a department head.
  module Personas
    # First match wins, so the more specific titles come first: "Chief Financial
    # Officer" is finance, not a CEO; "General Manager" is not "Managing Director".
    RULES = [
      [/\b(cfo|chief financial|finance|financial controller|accounts?|accounting)\b|المالي|المالية|الحسابات/i,
       "CFO_FINANCE"],
      [/\b(cio|cto|chief (information|technology|digital)|it|information technology|technology|digital)\b|تقنية المعلومات|التقني/i,
       "IT_DIGITAL"],
      [/\b(coo|chief operating|general manager|gm)\b|المدير العام|مدير عام|العمليات التنفيذي/i, "GM_COO"],
      [/\b(ceo|chief executive|owner|co-?founder|founder|managing director|md|chair(man|woman|person)?|president|proprietor)\b|الرئيس التنفيذي|مالك|المالك|مؤسس|المؤسس|رئيس مجلس|العضو المنتدب/i,
       "CEO_OWNER_MD"],
      [/\b(sales|commercial|business development|revenue)\b|المبيعات|التجاري/i, "SALES_COMMERCIAL"],
      [/\b(procurement|purchasing|supply chain|sourcing|buying)\b|المشتريات|سلسلة الإمداد|التوريد/i,
       "PROCUREMENT_SUPPLY"],
      [/\b(marketing|brand|communications)\b|التسويق/i, "MARKETING"],
      [/\b(customer (service|support|care|experience)|service desk)\b|خدمة العملاء/i, "CUSTOMER_SERVICE"],
      [/\b(hr|human resources|people|talent|personnel)\b|الموارد البشرية|شؤون الموظفين/i, "HR"],
      [/\b(operations|logistics|warehouse|fulfil+ment|production|plant)\b|العمليات|المستودع|اللوجستي|الإنتاج/i,
       "OPERATIONS"],
      [/\b(head|director|manager|lead|vp|vice president)\b|مدير|رئيس قسم/i, "DEPARTMENT_HEAD"]
    ].freeze

    module_function

    def from_title(title)
      text = title.to_s.squish
      return "OTHER" if text.blank?

      RULES.each { |pattern, persona| return persona if text.match?(pattern) }
      "OTHER"
    end

    # The Doc 08 §8.2 column a persona is weighted by. Functional heads, and
    # anyone else with a defined scope, are weighted as department heads.
    def column(persona)
      case persona
      when "CEO_OWNER_MD" then :ceo
      when "GM_COO" then :gm
      else :department_head
      end
    end

    def company_wide?(persona) = %w[CEO_OWNER_MD GM_COO].include?(persona)
  end
end
