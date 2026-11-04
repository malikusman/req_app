/**
 * The shape of a form field and its answers, shared by the onboarding form and
 * the renderer that draws it.
 */

export type FieldType =
  | 'single_select'
  | 'multi_select'
  | 'searchable_select'
  | 'text'
  | 'textarea'
  /** Explanatory copy between questions. Stores nothing. */
  | 'static'
  /** One numeric input per option the user picked in `sourceField`. */
  | 'per_item_numeric'
  /** A multi-select where each selection can carry a short free-text detail. */
  | 'multi_select_with_detail'
  /** Pick items, then pick sub-options for each item picked. */
  | 'two_stage_matrix'
  /** Several labelled inputs that together form one answer. */
  | 'parallel_text'
  /** One searchable row per category. */
  | 'category_matrix';

/**
 * Essential is the only tier that counts toward the completion percent.
 * Recommended and Optional are worth asking but must never hold someone at 99%.
 */
export type FieldTier = 'essential' | 'recommended' | 'optional' | 'conditional';

export type OptionGroup = { label: string; options: string[] };
export type MatrixCategory = { id: string; label: string; options: string[] };

export type QuestionnaireField = {
  id: string;
  type: FieldType;
  label: string;
  helper?: string;
  tier?: FieldTier;
  options?: string[];
  groups?: OptionGroup[];
  maxSelections?: number;
  placeholder?: string;
  /** Reveals a free-text "Please specify" box when an "Other" option is chosen. */
  withOther?: boolean;
  /** Gives each selection its own short detail input. */
  withDetail?: boolean;
  detailPlaceholder?: string;
  /** per_item_numeric: the multi-select whose selections become the rows. */
  sourceField?: string;
  /** per_item_numeric: the opt-out shown beside each row. */
  unknownLabel?: string;
  /** two_stage_matrix: the sub-options offered for each chosen item. */
  channelOptions?: string[];
  stageOneLabel?: string;
  stageTwoLabel?: string;
  /** parallel_text: one input per label, answered in order. */
  subLabels?: string[];
  /** category_matrix: one searchable row per category. */
  categories?: MatrixCategory[];
  /** Shown only once `field` is answered and the answer is not one of `notOneOf`. */
  showWhen?: { field: string; notOneOf: string[] };
  /** multi_select: choices that stand alone ("Not sure", "None") — picking one clears the rest. */
  exclusiveOptions?: string[];
  /** text / textarea: offer a "Not sure" tick box (Doc 07 §6 — every fact may be unknown). */
  allowUnknown?: boolean;
};

/** A group of questions shown together under one step. */
export type QuestionnaireScreen = { id: string; fields: QuestionnaireField[] };

export type QuestionnaireStep = {
  id: number;
  title: string;
  shortTitle: string;
  screens: QuestionnaireScreen[];
};

/** An answer is a scalar, a list, or — for the matrix questions — a keyed map. */
export type AnswerValue = string | string[] | Record<string, string | string[]> | undefined;
export type QuestionnaireAnswers = Record<string, AnswerValue>;

/** The answer a key user gives when they don't know (Doc 07 §6). */
export const NOT_SURE = 'Not sure';

/** The free-text companion for an "Other" choice. */
export const otherKey = (fieldId: string) => `${fieldId}_other`;
/** The per-selection detail companion. */
export const detailKey = (fieldId: string) => `${fieldId}_detail`;

export function fieldIsVisible(field: QuestionnaireField, answers: QuestionnaireAnswers): boolean {
  if (!field.showWhen) return true;
  const current = answers[field.showWhen.field];
  const value = Array.isArray(current) ? current[0] : current;
  if (!value || typeof value !== 'string') return false;
  return !field.showWhen.notOneOf.includes(value);
}

export function valuesEqual(a: AnswerValue, b: AnswerValue): boolean {
  if (Array.isArray(a) || Array.isArray(b)) {
    const arrA = Array.isArray(a) ? a : [];
    const arrB = Array.isArray(b) ? b : [];
    if (arrA.length !== arrB.length) return false;
    return arrA.every((v, i) => v === arrB[i]);
  }
  // The matrix questions store a keyed map. Comparing serialisations is enough
  // here: the values are small, and both sides are built by the same code.
  if ((a && typeof a === 'object') || (b && typeof b === 'object')) {
    return JSON.stringify(a ?? null) === JSON.stringify(b ?? null);
  }
  return a === b;
}

/** The answers in `current` that differ from `base`. */
export function diffAnswers(current: QuestionnaireAnswers, base: QuestionnaireAnswers): QuestionnaireAnswers {
  const diff: QuestionnaireAnswers = {};
  for (const key of Object.keys(current)) {
    if (!valuesEqual(current[key], base[key])) diff[key] = current[key];
  }
  return diff;
}
