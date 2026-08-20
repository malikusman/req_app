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
    screens: [{ id: '2a', fields: [] }, { id: '2b', fields: [] }],
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