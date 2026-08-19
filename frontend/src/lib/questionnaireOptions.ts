/** AI onboarding questionnaire — 10 sections, soft-required fields. */

export type FieldType =
  | 'single_select'
  | 'multi_select'
  | 'searchable_select'
  | 'text'
  | 'textarea'
  | 'per_item_numeric'
  | 'two_stage_matrix'
  | 'multi_select_with_detail'
  | 'parallel_text'
  | 'category_matrix';

export type FieldTier = 'essential' | 'recommended' | 'optional' | 'conditional';

export type FieldCondition =
  | { field: string; equals: string | string[] }
  | { field: string; notEquals: string | string[] }
  | { field: string; present: boolean }
  | { field: string; anyOf: string[] };

export type QuestionnaireField = {
  id: string;
  type: FieldType;
  label: string;
  options?: string[];
  maxSelections?: number;
  placeholder?: string;
  /** Completion tier; Essential only counts toward completion % in v2 */
  tier?: FieldTier;
  /** Show only when answers[key] satisfies the condition */
  showWhen?: FieldCondition;
};

export type QuestionnaireSection = {
  id: number;
  title: string;
  shortTitle: string;
  fields: QuestionnaireField[];
};

export const QUESTIONNAIRE_SECTIONS: QuestionnaireSection[] = [
  {
    id: 1,
    title: 'Company Profile',
    shortTitle: 'Profile',
    fields: [
      {
        id: 'company_industry',
        type: 'searchable_select',
        label: 'What industry is your company in?',
        options: [
          'Retail & E-commerce',
          'Manufacturing',
          'Construction & Engineering',
          'Healthcare & Medical',
          'Real Estate',
          'Logistics & Transportation',
          'Hospitality & Food Service',
          'Professional Services (Legal/Consulting/Accounting)',
          'Financial Services & Insurance',
          'Education',
          'IT & Software',
          'Energy & Utilities',
          'Automotive',
          'Agriculture',
          'Media & Entertainment',
          'Government & Public Sector',
          'Other',
        ],
      },
      {
        id: 'company_size',
        type: 'single_select',
        label: 'How many employees does your company have?',
        options: ['1–10', '11–50', '51–200', '201–500', '500+'],
      },
      {
        id: 'company_location',
        type: 'searchable_select',
        label: 'Where is your company headquartered?',
        options: [
          'United Arab Emirates',
          'Saudi Arabia',
          'Qatar',
          'Kuwait',
          'Bahrain',
          'Oman',
          'United States',
          'United Kingdom',
          'India',
          'Pakistan',
          'Egypt',
          'Jordan',
          'Lebanon',
          'Germany',
          'France',
          'Singapore',
          'Australia',
          'Canada',
          'South Africa',
          'Other',
        ],
      },
      {
        id: 'business_model',
        type: 'multi_select',
        label: 'How would you describe your business model?',
        options: ['B2B', 'B2C', 'B2B2C', 'Marketplace', 'Subscription/SaaS', 'Project-based'],
      },
      {
        id: 'annual_revenue',
        type: 'single_select',
        label: 'What is your approximate annual revenue? (optional)',
        options: ['Prefer not to say', '<$500K', '$500K–$2M', '$2M–$10M', '$10M–$50M', '$50M+'],
      },
    ],
  },
  {
    id: 2,
    title: 'Departments & Operations',
    shortTitle: 'Departments',
    fields: [
      {
        id: 'departments_present',
        type: 'multi_select',
        label: 'Which departments exist in your organization?',
        options: [
          'Sales',
          'Marketing',
          'Customer Support',
          'Operations',
          'Finance & Accounting',
          'HR & Recruiting',
          'IT',
          'Procurement',
          'Legal',
          'R&D/Product',
          'Logistics/Supply Chain',
          'Executive/Admin',
        ],
      },
      {
        id: 'operational_structure',
        type: 'single_select',
        label: 'How centralized is your operational decision-making?',
        options: [
          'Highly centralized (HQ-driven)',
          'Mostly centralized',
          'Mixed (some regional autonomy)',
          'Highly decentralized/branch-driven',
        ],
      },
      {
        id: 'num_locations',
        type: 'single_select',
        label: 'How many physical locations/branches do you operate?',
        options: ['1 (single site)', '2–5', '6–20', '20+', 'Fully remote/no physical site'],
      },
      {
        id: 'department_pain_point',
        type: 'text',
        label: 'Which department struggles most with manual work? (optional)',
        placeholder: 'e.g. Finance, Ops…',
      },
    ],
  },
  {
    id: 3,
    title: 'Current Technology',
    shortTitle: 'Technology',
    fields: [
      {
        id: 'erp_system',
        type: 'searchable_select',
        label: 'What ERP system (if any) do you use?',
        options: [
          'None',
          'SAP',
          'Oracle NetSuite',
          'Microsoft Dynamics 365/SL/BC',
          'Odoo',
          'Sage',
          'Infor',
          'Epicor',
          'Custom/In-house',
          'Other',
        ],
      },
      {
        id: 'crm_system',
        type: 'searchable_select',
        label: 'What CRM do you use?',
        options: [
          'None',
          'Salesforce',
          'HubSpot',
          'Zoho CRM',
          'Microsoft Dynamics CRM',
          'Pipedrive',
          'Monday CRM',
          'Custom/In-house',
          'Other',
        ],
      },
      {
        id: 'accounting_software',
        type: 'searchable_select',
        label: 'What accounting/finance software do you use?',
        options: [
          'None',
          'QuickBooks',
          'Xero',
          'Sage',
          'Microsoft Dynamics SL/BC',
          'Oracle Financials',
          'Excel/Spreadsheets only',
          'Other',
        ],
      },
      {
        id: 'hr_software',
        type: 'searchable_select',
        label: 'What HR/payroll system do you use? (optional)',
        options: [
          'None',
          'BambooHR',
          'Workday',
          'SAP SuccessFactors',
          'Zoho People',
          'ADP',
          'Local/manual (Excel)',
          'Other',
        ],
      },
      {
        id: 'communication_tools',
        type: 'multi_select',
        label: 'Which communication/collaboration tools does your team use?',
        options: [
          'Email (Outlook/Gmail)',
          'Slack',
          'Microsoft Teams',
          'WhatsApp Business',
          'Zoom',
          'Google Workspace',
          'Other',
        ],
      },
      {
        id: 'tech_stack_maturity',
        type: 'single_select',
        label: 'How would you rate your overall software/tech maturity?',
        options: [
          'Mostly manual/paper-based',
          'Basic tools (Excel, email)',
          'Some systems, not well integrated',
          'Well-integrated modern stack',
        ],
      },
    ],
  },
  {
    id: 4,
    title: 'Business Processes',
    shortTitle: 'Processes',
    fields: [
      {
        id: 'manual_processes',
        type: 'multi_select',
        label: 'Which of these are still done manually or on spreadsheets?',
        options: [
          'Data entry',
          'Invoicing/billing',
          'Reporting',
          'Inventory tracking',
          'Scheduling',
          'Approvals',
          'Customer follow-ups',
          'Expense tracking',
          'Order processing',
          'Compliance checks',
          'None of the above',
        ],
      },
      {
        id: 'repetitive_task_frequency',
        type: 'single_select',
        label: 'How often does your team perform repetitive, rule-based tasks?',
        options: ['Daily', 'Several times a week', 'Weekly', 'Rarely', 'Not sure'],
      },
      {
        id: 'approval_workflow',
        type: 'single_select',
        label: 'How are internal approvals handled?',
        options: [
          'Fully digital/automated workflow',
          'Email-based approvals',
          'Paper/in-person sign-off',
          'Mixed',
        ],
      },
      {
        id: 'reporting_frequency',
        type: 'single_select',
        label: 'How often are business reports generated?',
        options: [
          'Real-time/automated dashboards',
          'Weekly',
          'Monthly',
          'Quarterly or less',
          'Ad hoc/on request',
        ],
      },
    ],
  },
  {
    id: 5,
    title: 'Data & Documents',
    shortTitle: 'Documents',
    fields: [
      {
        id: 'data_storage_location',
        type: 'multi_select',
        label: 'Where is your company data primarily stored?',
        options: [
          'Cloud storage (Google Drive/OneDrive/Dropbox)',
          'On-premise servers',
          'ERP/CRM system',
          'Local employee computers',
          'Physical/paper files',
          'Other',
        ],
      },
      {
        id: 'document_types',
        type: 'multi_select',
        label: 'What types of documents does your business manage regularly?',
        options: [
          'Contracts',
          'Invoices & receipts',
          'Reports',
          'HR/employee records',
          'Technical/engineering documents',
          'Customer records',
          'Policies & SOPs',
          'Emails/correspondence',
        ],
      },
      {
        id: 'document_volume',
        type: 'single_select',
        label: 'Roughly how many documents does your company handle per month? (optional)',
        options: ['<50', '50–200', '200–1000', '1000+', 'Not sure'],
      },
      {
        id: 'search_difficulty',
        type: 'single_select',
        label: 'How easy is it for employees to find internal information/documents?',
        options: [
          'Very easy — centralized & searchable',
          'Somewhat easy',
          'Difficult — scattered across systems',
          'Very difficult — mostly tribal knowledge',
        ],
      },
    ],
  },
  {
    id: 6,
    title: 'Customer Engagement',
    shortTitle: 'Customers',
    fields: [
      {
        id: 'customer_channels',
        type: 'multi_select',
        label: 'How do customers primarily reach your company?',
        options: [
          'Phone calls',
          'Email',
          'WhatsApp',
          'Live chat/website',
          'Social media',
          'In-person',
          'Mobile app',
          'Third-party marketplace',
        ],
      },
      {
        id: 'monthly_inquiry_volume',
        type: 'single_select',
        label: 'Approximately how many customer inquiries do you receive per month?',
        options: ['<100', '100–500', '500–2,000', '2,000–10,000', '10,000+'],
      },
      {
        id: 'response_time_current',
        type: 'single_select',
        label: "What's your typical customer response time today?",
        options: ['Instant/automated', 'Within hours', 'Within a day', '1–3 days', '3+ days'],
      },
      {
        id: 'support_team_size',
        type: 'single_select',
        label: 'How many people handle customer support/inquiries? (optional)',
        options: ['No dedicated team', '1–3', '4–10', '11–30', '30+'],
      },
    ],
  },
  {
    id: 7,
    title: 'Business Challenges',
    shortTitle: 'Challenges',
    fields: [
      {
        id: 'top_bottlenecks',
        type: 'multi_select',
        label: 'What are your biggest operational bottlenecks? (choose up to 3)',
        maxSelections: 3,
        options: [
          'Slow customer response times',
          'Manual/repetitive data entry',
          'Disconnected systems (no integration)',
          'Lack of visibility into performance/KPIs',
          'Long approval cycles',
          'Difficulty finding information',
          'High employee workload',
          'Errors from manual processes',
          'Slow reporting/decision-making',
          'Scaling issues with growth',
        ],
      },
      {
        id: 'time_lost_estimate',
        type: 'single_select',
        label: 'Roughly how much staff time per week is lost to repetitive manual tasks? (optional)',
        options: ['<5 hours', '5–15 hours', '15–40 hours', '40+ hours', 'Not sure'],
      },
      {
        id: 'error_prone_areas',
        type: 'multi_select',
        label: 'Where do errors or inconsistencies happen most often? (optional)',
        options: [
          'Data entry',
          'Invoicing/billing',
          'Reporting',
          'Inventory/stock',
          'Scheduling',
          'Customer records',
          'None significant',
        ],
      },
    ],
  },
  {
    id: 8,
    title: 'AI Readiness',
    shortTitle: 'AI',
    fields: [
      {
        id: 'current_ai_usage',
        type: 'single_select',
        label: 'Does your company currently use any AI tools?',
        options: [
          'No, not yet',
          'Yes, occasionally (e.g., ChatGPT for individual tasks)',
          'Yes, integrated into some workflows',
          'Yes, AI is core to our operations',
        ],
      },
      {
        id: 'ai_tools_used',
        type: 'multi_select',
        label: 'Which AI tools/platforms are you currently using?',
        options: [
          'ChatGPT/Claude (general use)',
          'Copilot (Microsoft)',
          'CRM-built-in AI features',
          'Chatbot/customer support AI',
          'Custom-built AI solution',
          'Other',
        ],
        showWhen: { field: 'current_ai_usage', notEquals: 'No, not yet' },
      },
      {
        id: 'desired_ai_functions',
        type: 'multi_select',
        label: 'Which areas would you most like AI to improve?',
        options: [
          'Customer support automation',
          'Internal knowledge search (RAG)',
          'Workflow/process automation',
          'Reporting & analytics automation',
          'Email drafting/management',
          'Sales assistance',
          'HR/recruiting assistance',
          'Finance/accounting automation',
          'Document processing',
          'Not sure yet',
        ],
      },
      {
        id: 'ai_openness',
        type: 'single_select',
        label: 'How ready is your team/organization to adopt new AI tools?',
        options: [
          'Very ready — actively looking',
          'Ready with the right guidance',
          'Cautious — need to see proof first',
          'Not ready yet',
        ],
      },
    ],
  },
  {
    id: 9,
    title: 'Security & Infrastructure',
    shortTitle: 'Security',
    fields: [
      {
        id: 'data_hosting',
        type: 'single_select',
        label: 'Where is your business data primarily hosted?',
        options: ['Public cloud (AWS/Azure/GCP)', 'Private/on-premise servers', 'Hybrid', 'Not sure'],
      },
      {
        id: 'compliance_requirements',
        type: 'multi_select',
        label: 'Do any of these apply to your business? (optional)',
        options: [
          'GDPR',
          'HIPAA',
          'Local data residency requirements',
          'ISO 27001 / security certifications',
          'None of the above',
          'Not sure',
        ],
      },
      {
        id: 'security_posture',
        type: 'single_select',
        label: 'How would you describe your current data security setup? (optional)',
        options: [
          'Formal security policies & tools in place',
          'Basic security measures only',
          'No formal security practices',
          'Not sure',
        ],
      },
    ],
  },
  {
    id: 10,
    title: 'Business Goals',
    shortTitle: 'Goals',
    fields: [
      {
        id: 'primary_goals',
        type: 'multi_select',
        label: 'What outcomes matter most to you right now? (choose up to 3)',
        maxSelections: 3,
        options: [
          'Reduce operational costs',
          'Save employee time',
          'Increase productivity',
          'Improve customer service/response time',
          'Improve data accuracy',
          'Better visibility/reporting',
          'Scale operations without adding headcount',
          'Improve employee experience',
        ],
      },
      {
        id: 'timeline',
        type: 'single_select',
        label: "What's your timeline for adopting AI solutions?",
        options: ['Immediately (this month)', 'Within 3 months', 'Within 6–12 months', 'Just exploring'],
      },
      {
        id: 'budget_range',
        type: 'single_select',
        label: "What's your approximate budget range for AI adoption? (optional)",
        options: ['Prefer not to say', '<$5K', '$5K–$20K', '$20K–$50K', '$50K+'],
      },
      {
        id: 'additional_context',
        type: 'textarea',
        label: 'Anything else we should know about your business or goals? (optional)',
        placeholder: 'Optional context for our analysis…',
      },
    ],
  },
];

export type QuestionnaireAnswers = Record<string, string | string[] | undefined>;

export function fieldIsVisible(field: QuestionnaireField, answers: QuestionnaireAnswers): boolean {
  const condition = field.showWhen;
  if (!condition) return true;

  const current = answers[condition.field];
  const values = Array.isArray(current) ? current : typeof current === 'string' && current.trim() ? [current] : [];

  if ('equals' in condition) {
    const expected = Array.isArray(condition.equals) ? condition.equals : [condition.equals];
    return values.some((v) => expected.includes(v));
  }
  if ('notEquals' in condition) {
    const first = Array.isArray(current) ? current[0] : current;
    if (!first) return false;
    const excluded = Array.isArray(condition.notEquals) ? condition.notEquals : [condition.notEquals];
    return !excluded.includes(first);
  }
  if ('present' in condition) {
    return condition.present ? values.length > 0 : values.length === 0;
  }
  if ('anyOf' in condition) {
    return values.some((v) => condition.anyOf.includes(v));
  }
  return true;
}

export function computeCompletionPercent(answers: QuestionnaireAnswers): number {
  const fields = QUESTIONNAIRE_SECTIONS.flatMap((s) => s.fields).filter((f) => fieldIsVisible(f, answers));
  if (fields.length === 0) return 0;
  const answered = fields.filter((f) => {
    const v = answers[f.id];
    if (Array.isArray(v)) return v.length > 0;
    return Boolean(v && String(v).trim());
  }).length;
  return Math.round((answered / fields.length) * 100);
}

export function sectionTouched(sectionId: number, answers: QuestionnaireAnswers): boolean {
  const section = QUESTIONNAIRE_SECTIONS.find((s) => s.id === sectionId);
  if (!section) return false;
  return section.fields.some((f) => {
    if (!fieldIsVisible(f, answers)) return false;
    const v = answers[f.id];
    if (Array.isArray(v)) return v.length > 0;
    return Boolean(v && String(v).trim());
  });
}
