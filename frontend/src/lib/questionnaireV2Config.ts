import type { QuestionnaireField, QuestionnaireSection } from './questionnaireOptions';
import { QUESTIONNAIRE_SECTIONS } from './questionnaireOptions';

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
    screens: [{ id: '1', fields: [] }],
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