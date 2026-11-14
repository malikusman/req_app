/**
 * The company onboarding form (Doc 07 §6–7): eleven factual fields, participant
 * planning and the key user's language, on one short screen.
 *
 * The backend authority on what may be stored is Companies::OnboardingFields;
 * a spec reads this file and checks the ids, "Other" companions and option lists
 * match, so a change here must be made there too. Every list is written out in
 * full for that reason.
 *
 * Nothing here asks about goals, pain points, budget, revenue or readiness —
 * those belong in the conversation with leadership (Doc 07 §2).
 */
import { NOT_SURE, type QuestionnaireField } from './formFields';
import { COUNTRIES } from './countries';

export type OnboardingGroup = { id: number; title: string; intro?: string; fields: QuestionnaireField[] };

export const ONBOARDING_GROUPS: OnboardingGroup[] = [
  {
    id: 1,
    title: 'About the company',
    fields: [
      {
        id: 'o01_industry',
        type: 'searchable_select',
        label: 'What industry is your company in?',
        options: [
          'Wholesale & distribution',
          'Retail & e-commerce',
          'Manufacturing',
          'Logistics & transport',
          'Construction & engineering',
          'Real estate',
          'Professional services',
          'Financial services & insurance',
          'Healthcare',
          'Hospitality & food',
          'Education',
          'Technology & software',
          'Energy & utilities',
          'Automotive',
          'Media & marketing',
          'Government & public sector',
          'Agriculture & food production',
          'Other',
          'Not sure',
        ],
        withOther: true,
      },
      {
        id: 'o01_industry_detail',
        type: 'text',
        label: 'In a few words, what exactly do you do?',
        placeholder: 'e.g. Wholesale of tailoring materials and garment accessories',
      },
      {
        id: 'o02_headcount',
        type: 'single_select',
        label: 'Approximately how many people work in the company?',
        options: ['1–10', '11–50', '51–200', '201–500', '501–1,000', '1,000+', 'Not sure'],
      },
      {
        id: 'o03_hq_country',
        type: 'searchable_select',
        label: 'Where is the company headquartered?',
        options: [...COUNTRIES, NOT_SURE],
      },
      {
        id: 'o03_locations',
        type: 'text',
        label: 'Which other locations or branches matter?',
        placeholder: 'e.g. Dubai, Riyadh, Lagos',
        allowUnknown: true,
      },
      {
        id: 'o04_business_model',
        type: 'multi_select',
        label: 'How does the company mainly operate?',
        options: [
          'B2B',
          'B2C',
          'B2B2C',
          'Wholesale',
          'Retail',
          'Distribution',
          'Manufacturing',
          'Services',
          'Project-based',
          'Marketplace',
          'Subscription',
          'Other',
          'Not sure',
        ],
        withOther: true,
        exclusiveOptions: [NOT_SURE],
      },
      {
        id: 'o05_products_services',
        type: 'textarea',
        label: 'What are your main products or services?',
        placeholder: 'One or two sentences is plenty.',
        allowUnknown: true,
      },
      {
        id: 'o06_departments',
        type: 'multi_select',
        label: 'Which departments or functions exist?',
        options: [
          'Sales',
          'Procurement',
          'Finance',
          'Operations',
          'Warehouse & logistics',
          'Customer service',
          'HR',
          'IT',
          'Marketing',
          'Administration',
          'Management',
          'Other',
          'Not sure',
        ],
        withOther: true,
        exclusiveOptions: [NOT_SURE],
      },
    ],
  },
  {
    id: 2,
    title: 'How work arrives and where it lives',
    fields: [
      {
        id: 'o07_channels',
        type: 'multi_select',
        label: 'How do customers and partners mainly reach you?',
        options: [
          'Email',
          'Phone',
          'WhatsApp',
          'Website',
          'Online store',
          'Social media',
          'Marketplaces',
          'In person',
          'Other',
          'Not sure',
        ],
        withOther: true,
        exclusiveOptions: [NOT_SURE],
      },
      {
        id: 'o08_systems',
        type: 'multi_select',
        label: 'Which core business systems do you use?',
        helper: 'Name the actual products under "Other" if you like — e.g. Zoho Books, SAP Business One.',
        options: [
          'ERP',
          'CRM',
          'Accounting software',
          'HR or payroll system',
          'E-commerce platform',
          'Document storage',
          'Microsoft 365',
          'Google Workspace',
          'Spreadsheets',
          'Custom-built system',
          'Other',
          'Not sure',
        ],
        withOther: true,
        exclusiveOptions: [NOT_SURE],
      },
      {
        id: 'o09_data_storage',
        type: 'multi_select',
        label: 'Where are important files and data mainly kept?',
        options: [
          'Cloud suite (Microsoft 365, Google Workspace)',
          'Shared network drives',
          'Local servers',
          'Inside the ERP or CRM',
          'Spreadsheets',
          'A mix of these',
          'Other',
          'Not sure',
        ],
        withOther: true,
        exclusiveOptions: [NOT_SURE],
      },
      {
        id: 'o10_ai_tools',
        type: 'multi_select',
        label: 'Which AI tools are already used, if any?',
        options: [
          'None',
          'ChatGPT',
          'Microsoft Copilot',
          'Google Gemini',
          'Claude',
          'AI built into our existing software',
          'A chatbot on our website',
          'Other',
          'Not sure',
        ],
        withOther: true,
        exclusiveOptions: ['None', NOT_SURE],
      },
      {
        id: 'o11_constraints',
        type: 'multi_select',
        label: 'Are there security, regulatory or data-residency constraints we should know from the start?',
        options: [
          'Data must stay in the country',
          'Industry regulation',
          'Security certification (e.g. ISO 27001)',
          'Client confidentiality obligations',
          'Internal rules on cloud systems',
          'Internal rules on AI tools',
          'Other',
          'Not sure',
        ],
        withOther: true,
        exclusiveOptions: [NOT_SURE],
      },
    ],
  },
  {
    id: 3,
    title: 'Who takes part',
    intro:
      'Choose people who know the day-to-day work well. You can start with a few people and add more later. A handful of well-chosen participants is usually enough for a first engagement.',
    fields: [
      {
        id: 'p1_departments',
        type: 'multi_select',
        label: 'Which departments should take part?',
        // The client's own departments: filled in from the answer above and the
        // engagement's scope when the form is drawn.
        options: [],
      },
      {
        id: 'p2_department_counts',
        type: 'per_item_numeric',
        label: 'How many people from each will take part?',
        helper: 'A rough number is fine. If you are not sure yet, we will settle it with you before agreeing the fee.',
        sourceField: 'p1_departments',
        unknownLabel: 'Not sure',
      },
      {
        id: 'a4_language',
        type: 'single_select',
        label: 'Which language would you like us to use with you?',
        options: ['English', 'Arabic'],
      },
    ],
  },
];

export const ONBOARDING_FIELDS: QuestionnaireField[] = ONBOARDING_GROUPS.flatMap((g) => g.fields);
