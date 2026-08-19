import type { QuestionnaireField } from './questionnaireOptions';

export type QuestionnaireV2Screen = {
  id: string;
  fields: QuestionnaireField[];
};

export type QuestionnaireV2Step = {
  id: number;
  screens: QuestionnaireV2Screen[];
};

export const QUESTIONNAIRE_V2_STEPS: QuestionnaireV2Step[] = [
  { id: 1, screens: [{ id: '1', fields: [] }] },
  { id: 2, screens: [{ id: '2a', fields: [] }, { id: '2b', fields: [] }] },
  { id: 3, screens: [{ id: '3a', fields: [] }, { id: '3b', fields: [] }, { id: '3c', fields: [] }] },
  { id: 4, screens: [{ id: '4a', fields: [] }, { id: '4b', fields: [] }] },
  { id: 5, screens: [{ id: '5', fields: [] }] },
  { id: 6, screens: [{ id: '6', fields: [] }] },
  { id: 7, screens: [{ id: '7', fields: [] }] },
  { id: 8, screens: [{ id: '8', fields: [] }] },
];