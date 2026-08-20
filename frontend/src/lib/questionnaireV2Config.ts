import type { QuestionnaireField, QuestionnaireSection } from './questionnaireOptions';
import { QUESTIONNAIRE_SECTIONS } from './questionnaireOptions';
import { COUNTRIES } from './countries';

export type QuestionnaireV2Screen = {
  id: string;
  fields: QuestionnaireField[];
};

export type QuestionnaireV2Step = {
  id: number;
  title: string;
  shortTitle: string;
  screens: QuestionnaireV2Screen[];
};

export const QUESTIONNAIRE_V2_STEPS: QuestionnaireV2Step[] = [
  {
    id: 1,
    title: 'About Your Business',
    shortTitle: 'Business',
    screens: [
      {
        id: '1',
        fields: [
          {
            id: 'q01_primary_industry',
            type: 'searchable_select',
            label: "What is your company's primary industry?",
            options: [
              'Retail & E-commerce',
              'Manufacturing',
              'Construction & Engineering',
              'Healthcare & Medical',
              'Real Estate',
              'Logistics & Transportation',
              'Hospitality & Food Service',
              'Professional Services',
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
            id: 'q02_business_description',
            type: 'textarea',
            label: 'Briefly describe your business. What are your main products or services, and who are your main customers?',
            helper: 'A few sentences are enough. 100–1,500 chars.',
          },
          {
            id: 'q03_employee_count',
            type: 'single_select',
            label: 'How many employees does your company have?',
            options: ['1–10', '11–25', '26–50', '51–100', '101–250', '251–500', '501–1,000', '1,000+'],
          },
          {
            id: 'q04_headquarters_country',
            type: 'searchable_select',
            label: 'Where is your company headquartered?',
            options: COUNTRIES,
          },
          {
            id: 'q05_customer_types',
            type: 'multi_select',
            label: 'Who does your company primarily sell to or serve?',
            options: ['Businesses', 'Consumers', 'Government / public sector', 'Other'],
          },
          {
            id: 'q06_operating_sites',
            type: 'single_select',
            label: 'How many physical offices, branches, stores, warehouses, factories or other operating sites does your company have?',
            options: ['1', '2–5', '6–20', '21–50', '51+', 'Fully remote / no permanent operating site'],
          },
        ],
      },
    ],
  },
  {
    id: 2,
    title: 'Organisation & Business Processes',
    shortTitle: 'Organisation',
    screens: [
      {
        id: '2a',
        fields: [
          {
            id: 'q07_departments',
            type: 'multi_select',
            label: 'Which departments or functions exist in your organisation?',
            options: [
              'Sales',
              'Marketing',
              'Customer Service / Support',
              'Operations',
              'Finance & Accounting',
              'HR & Recruitment',
              'IT',
              'Procurement / Purchasing',
              'Legal / Compliance',
              'R&D / Product',
              'Logistics / Supply Chain',
              'Production / Manufacturing',
              'Project Management / Delivery',
              'Quality Control',
              'Executive / Administration',
              'Other',
            ],
          },
          {
            id: 'q08_department_headcount',
            type: 'text',
            label: 'Approximately how many employees work in each selected department or function?',
            helper: 'Approx. headcount per department',
            tier: 'recommended',
          },
          {
            id: 'q09_core_processes',
            type: 'multi_select',
            label: 'Which processes are important to the day-to-day running of your business?',
            groups: [
              {
                label: 'Sales & Customer',
                options: ['lead generation / sales', 'quotations / proposals', 'order processing', 'customer service'],
              },
              {
                label: 'Supply & Operations',
                options: [
                  'procurement / purchasing',
                  'supplier management',
                  'inventory / warehouse',
                  'logistics / delivery',
                  'production / manufacturing',
                  'project management / delivery',
                ],
              },
              {
                label: 'Corporate & Support',
                options: [
                  'finance / accounting',
                  'collections / payment follow-up',
                  'HR / recruitment',
                  'payroll',
                  'reporting / MI',
                  'internal approvals',
                  'compliance / quality control',
                  'document processing',
                  'scheduling',
                  'Other',
                ],
              },
            ],
          },
        ],
      },
      {
        id: '2b',
        fields: [
          {
            id: 'q10_process_documentation',
            type: 'single_select',
            label: "How well documented are your company's main processes?",
            options: [
              'Most major processes are formally documented',
              'Some processes are documented',
              'Documentation is limited',
              'We do not have formal process documentation',
              'Not sure',
            ],
          },
          {
            id: 'q10a_documentation_types',
            type: 'multi_select',
            label: 'What types of process documentation are available?',
            tier: 'conditional',
            options: [
              'SOPs',
              'ISO procedures / work instructions',
              'Process maps / flowcharts',
              'Departmental procedures',
              'Policies',
              'Quality manuals',
              'Checklists',
              'Training manuals',
              'Forms / templates',
              'Compliance procedures',
              'Other',
              'Not sure',
            ],
          },
          {
            id: 'q10b_certifications',
            type: 'multi_select',
            label: 'Does your organisation hold any formal management-system certifications or process standards?',
            tier: 'optional',
            options: [
              'ISO 9001',
              'ISO 14001',
              'ISO 45001',
              'ISO 27001',
              'Other ISO certification',
              'Other formal certification / standard',
              'None',
              'Not sure',
            ],
          },
          {
            id: 'msg_process_documents',
            type: 'static',
            label:
              'You can upload procedures and process documents after onboarding. Worktruth can analyse them together with employee interviews to identify AI, automation and process-improvement opportunities.',
          },
          {
            id: 'q11_manual_process_areas',
            type: 'multi_select',
            label: 'Which areas do you believe currently involve the most manual or administrative work?',
            groups: [
              {
                label: 'Sales & Customer',
                options: ['lead generation / sales', 'quotations / proposals', 'order processing', 'customer service'],
              },
              {
                label: 'Supply & Operations',
                options: [
                  'procurement / purchasing',
                  'supplier management',
                  'inventory / warehouse',
                  'logistics / delivery',
                  'production / manufacturing',
                  'project management / delivery',
                ],
              },
              {
                label: 'Corporate & Support',
                options: [
                  'finance / accounting',
                  'collections / payment follow-up',
                  'HR / recruitment',
                  'payroll',
                  'reporting / MI',
                  'internal approvals',
                  'compliance / quality control',
                  'document processing',
                  'scheduling',
                  'Other',
                ],
              },
              { label: '', options: ['Not sure'] },
            ],
          },
          {
            id: 'q12_department_handoffs',
            type: 'textarea',
            label:
              'Are there any areas where one department regularly has to wait for, chase or manually exchange information with another department?',
            tier: 'optional',
            helper: 'If yes, briefly describe one or two examples.',
          },
          {
            id: 'q13_key_person_dependency',
            type: 'textarea',
            label:
              'Are there important tasks or processes that depend heavily on the knowledge of one or a few employees?',
            tier: 'optional',
            helper:
              "For example: only one employee knows how to prepare an important report, or key data lives only in one employee's files.",
          },
          {
            id: 'q14_approval_methods',
            type: 'multi_select',
            label: 'How are internal approvals usually handled?',
            options: [
              'Automated workflow',
              'Through ERP or another business system',
              'Email',
              'Teams / Slack / internal messaging',
              'WhatsApp or similar',
              'Paper / printed forms',
              'Verbal / in person',
              'Combination of methods',
              'Very few approvals required',
              'Not sure',
            ],
          },
        ],
      },
    ],
  },
  {
    id: 3,
    title: 'How Work Gets Done',
    shortTitle: 'Work',
    screens: [{ id: '3a', fields: [] }, { id: '3b', fields: [] }, { id: '3c', fields: [] }],
  },
  {
    id: 4,
    title: 'Systems & Information',
    shortTitle: 'Systems',
    screens: [{ id: '4a', fields: [] }, { id: '4b', fields: [] }],
  },
  {
    id: 5,
    title: 'External Business Activity',
    shortTitle: 'External',
    screens: [{ id: '5', fields: [] }],
  },
  {
    id: 6,
    title: 'Challenges & Priorities',
    shortTitle: 'Challenges',
    screens: [{ id: '6', fields: [] }],
  },
  {
    id: 7,
    title: 'AI, Automation & Employee Readiness',
    shortTitle: 'AI & Readiness',
    screens: [{ id: '7', fields: [] }],
  },
  {
    id: 8,
    title: 'Governance & What You Want to Achieve',
    shortTitle: 'Governance',
    screens: [{ id: '8', fields: [] }],
  },
];

export function questionnaireSectionsFor(version: number): QuestionnaireSection[] {
  if (version < 2) return QUESTIONNAIRE_SECTIONS;
  return QUESTIONNAIRE_V2_STEPS.map((step) => ({
    id: step.id,
    title: step.title,
    shortTitle: step.shortTitle,
    fields: step.screens.flatMap((screen) => screen.fields),
  }));
}