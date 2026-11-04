import { useState } from 'react';
import { api, type CompanyFactsUpdate, type QuestionnaireAnswerMap } from '../../lib/api';
import { Button, Card } from '../../components/ui';
import { diffAnswers, type AnswerValue, type QuestionnaireAnswers } from '../../lib/formFields';
import { ONBOARDING_GROUPS } from '../../lib/onboardingFields';
import { FieldRenderer } from '../shared/FieldRenderer';

/** The facts groups of the onboarding form. Who takes part stays the key user's. */
const FACT_GROUPS = ONBOARDING_GROUPS.filter((group) => group.fields.every((field) => field.id.startsWith('o')));

/**
 * A consultant correcting the client's facts after onboarding (Doc 07 §12), on
 * the same fields the client filled in. Only what was changed is sent, so a
 * company whose old answers were set aside can have one fact corrected without
 * blanking the rest.
 */
export function CompanyFactsEditor({
  token,
  companyId,
  answers: initial,
  onSaved,
  onCancel,
}: {
  token: string;
  companyId: number;
  answers: QuestionnaireAnswerMap;
  onSaved: (result: CompanyFactsUpdate) => void;
  onCancel: () => void;
}) {
  const [answers, setAnswers] = useState<QuestionnaireAnswers>(initial as QuestionnaireAnswers);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const changes = diffAnswers(answers, initial as QuestionnaireAnswers);
  const changed = Object.keys(changes).length > 0;

  const setAnswer = (id: string, value: AnswerValue) => setAnswers((prev) => ({ ...prev, [id]: value }));

  const save = async () => {
    setSaving(true);
    setError('');
    try {
      onSaved(await api.updateConsultantCompanyFacts(token, companyId, changes as QuestionnaireAnswerMap));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not save the changes');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="space-y-4">
      <p className="m-0 text-sm text-muted-foreground">
        What you change is recorded as found in conversation, under your name, and kept in the change history.
      </p>
      {FACT_GROUPS.map((group) => (
        <Card key={group.id} title={group.title}>
          <div className="space-y-6">
            {group.fields.map((field) => (
              <FieldRenderer key={field.id} field={field} answers={answers} setAnswer={setAnswer} />
            ))}
          </div>
        </Card>
      ))}
      {error && <p className="m-0 text-sm text-status-error">{error}</p>}
      <div className="flex justify-end gap-2">
        <Button variant="secondary" onClick={onCancel}>
          Cancel
        </Button>
        <Button loading={saving} disabled={!changed} onClick={save}>
          Save changes
        </Button>
      </div>
    </div>
  );
}
