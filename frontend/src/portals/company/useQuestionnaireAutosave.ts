import { useMemo, useRef, useState, useEffect } from 'react';
import { api, ApiRequestError } from '../../lib/api';
import type {
  FieldType,
  QuestionnaireAnswers,
  QuestionnaireField,
  QuestionnaireSection,
} from '../../lib/questionnaireOptions';

export type AutosaveStatus = 'idle' | 'saving' | 'saved' | 'error';

const DEBOUNCE_MS = 1200;
const MAX_WAIT_MS = 5000;
const SAVING_DELAY_MS = 300;
const SAVED_FADE_MS = 2500;

// Field types that save immediately on change, per Stage 3A trigger rules. Any type
// not in this set (including text/textarea, and any not-yet-built advanced type
// currently rendered via a placeholder) is debounced — `static` is excluded entirely
// below and never reaches this set.
const IMMEDIATE_TYPES = new Set<FieldType>(['single_select', 'multi_select', 'searchable_select']);

function valuesEqual(a: string | string[] | undefined, b: string | string[] | undefined): boolean {
  if (Array.isArray(a) || Array.isArray(b)) {
    const arrA = Array.isArray(a) ? a : [];
    const arrB = Array.isArray(b) ? b : [];
    if (arrA.length !== arrB.length) return false;
    return arrA.every((v, i) => v === arrB[i]);
  }
  return a === b;
}

function diffAnswers(current: QuestionnaireAnswers, base: QuestionnaireAnswers): QuestionnaireAnswers {
  const diff: QuestionnaireAnswers = {};
  for (const key of Object.keys(current)) {
    if (!valuesEqual(current[key], base[key])) diff[key] = current[key];
  }
  return diff;
}

/**
 * v2-only autosave for the onboarding questionnaire. Always call this hook
 * unconditionally (React's rules of hooks require it) — pass `enabled: false`
 * for v1 and it stays fully inert: no timers, no requests, no beforeunload listener.
 */
export function useQuestionnaireAutosave(
  token: string | null,
  answers: QuestionnaireAnswers,
  sections: QuestionnaireSection[],
  enabled: boolean
) {
  const [status, setStatus] = useState<AutosaveStatus>('idle');

  const answersRef = useRef(answers);
  const enabledRef = useRef(enabled);
  const tokenRef = useRef(token);
  const lastSavedRef = useRef<QuestionnaireAnswers>(answers);
  const seededRef = useRef(false);

  // Refs must not be written during render (React Compiler rule) — keep them in
  // sync via an effect instead. Runs after every render, well before any
  // setTimeout/promise callback that reads them could possibly fire.
  useEffect(() => {
    answersRef.current = answers;
    enabledRef.current = enabled;
    tokenRef.current = token;
    if (!seededRef.current && enabled) {
      lastSavedRef.current = answers;
      seededRef.current = true;
    }
  });

  const fieldsById = useMemo(() => {
    const map = new Map<string, QuestionnaireField>();
    sections.forEach((section) => section.fields.forEach((field) => map.set(field.id, field)));
    return map;
  }, [sections]);

  const inFlightRef = useRef(false);
  const queuedRef = useRef(false);
  const authFailedRef = useRef(false);
  const debounceTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const maxWaitTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const savingDelayTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const savedFadeTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const waitersRef = useRef<Array<() => void>>([]);

  const isDirty = () => Object.keys(diffAnswers(answersRef.current, lastSavedRef.current)).length > 0;

  const clearScheduledTimers = () => {
    if (debounceTimerRef.current) clearTimeout(debounceTimerRef.current);
    if (maxWaitTimerRef.current) clearTimeout(maxWaitTimerRef.current);
    debounceTimerRef.current = null;
    maxWaitTimerRef.current = null;
  };

  const settleWaiters = () => {
    if (inFlightRef.current) return;
    const waiters = waitersRef.current;
    waitersRef.current = [];
    waiters.forEach((resolve) => resolve());
  };

  const triggerFlush = () => {
    if (!enabledRef.current || !tokenRef.current || authFailedRef.current) return;
    clearScheduledTimers();

    if (inFlightRef.current) {
      queuedRef.current = true;
      return;
    }

    const diff = diffAnswers(answersRef.current, lastSavedRef.current);
    if (Object.keys(diff).length === 0) {
      settleWaiters();
      return;
    }

    inFlightRef.current = true;

    if (savingDelayTimerRef.current) clearTimeout(savingDelayTimerRef.current);
    savingDelayTimerRef.current = setTimeout(() => setStatus('saving'), SAVING_DELAY_MS);

    let failed = false;

    api
      .updateQuestionnaireAnswers(tokenRef.current, diff)
      .then(() => {
        // Merge the snapshot that was actually sent, not the live answers — if the
        // user edited further while this request was in flight, those keys must
        // stay dirty so the next diff picks them up. See Stage 3A plan, Q1.
        lastSavedRef.current = { ...lastSavedRef.current, ...diff };
      })
      .catch((err: unknown) => {
        failed = true;
        if (err instanceof ApiRequestError && (err.status === 401 || err.status === 403)) {
          // Don't keep hammering a dead session — stop auto-retrying entirely.
          authFailedRef.current = true;
        }
        setStatus('error');
      })
      .finally(() => {
        if (savingDelayTimerRef.current) {
          clearTimeout(savingDelayTimerRef.current);
          savingDelayTimerRef.current = null;
        }
        inFlightRef.current = false;

        if (!failed && (queuedRef.current || isDirty())) {
          queuedRef.current = false;
          triggerFlush();
          return;
        }
        queuedRef.current = false;

        if (!failed) {
          setStatus('saved');
          if (savedFadeTimerRef.current) clearTimeout(savedFadeTimerRef.current);
          savedFadeTimerRef.current = setTimeout(() => setStatus('idle'), SAVED_FADE_MS);
        }
        settleWaiters();
      });
  };

  const notifyChange = (id: string) => {
    if (!enabledRef.current) return;
    // `field` is undefined for ids deliberately kept out of fieldsById — the "Other"
    // sidecar text keys (<field_id>_other). Those aren't static and aren't one of the
    // IMMEDIATE_TYPES, so they fall through to the debounced path below, matching the
    // set's own stated intent ("any type not in this set is debounced").
    const field = fieldsById.get(id);
    if (field?.type === 'static') return;

    if (field && IMMEDIATE_TYPES.has(field.type)) {
      triggerFlush();
      return;
    }

    if (debounceTimerRef.current) clearTimeout(debounceTimerRef.current);
    debounceTimerRef.current = setTimeout(triggerFlush, DEBOUNCE_MS);
    if (!maxWaitTimerRef.current) {
      maxWaitTimerRef.current = setTimeout(triggerFlush, MAX_WAIT_MS);
    }
  };

  const flush = (): Promise<void> => {
    if (!enabledRef.current) return Promise.resolve();
    return new Promise((resolve) => {
      waitersRef.current.push(resolve);
      triggerFlush();
    });
  };

  useEffect(() => {
    if (!enabled) return;
    const handler = (e: BeforeUnloadEvent) => {
      if (isDirty()) {
        e.preventDefault();
        e.returnValue = '';
      }
    };
    window.addEventListener('beforeunload', handler);
    return () => window.removeEventListener('beforeunload', handler);
  }, [enabled]);

  useEffect(() => {
    return () => {
      if (enabledRef.current) triggerFlush();
    };
    // Mount/unmount only — triggerFlush reads everything it needs via refs.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return { status, notifyChange, flush };
}
