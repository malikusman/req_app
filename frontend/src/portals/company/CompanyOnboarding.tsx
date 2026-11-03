import { useEffect, useMemo, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { api, type OnboardingState } from '../../lib/api';
import { useCompanyToken, useAuth } from '../../lib/auth';
import { PageHeader, Card, Input, Button, Skeleton } from '../../components/ui';
import { NOT_SURE, otherKey, type AnswerValue, type QuestionnaireAnswers, type QuestionnaireField } from '../../lib/formFields';
import { ONBOARDING_FIELDS, ONBOARDING_GROUPS } from '../../lib/onboardingFields';
import { FieldRenderer } from './questionnaire/FieldRenderer';
import { useFormAutosave } from './useFormAutosave';

const splitList = (text: AnswerValue) =>
  typeof text === 'string' ? text.split(/[,\n;]/).map((s) => s.trim()).filter(Boolean) : [];

/**
 * Company onboarding (Doc 07): one short screen of facts, who takes part, and the
 * confidentiality acknowledgement. Answers save as they are given; submitting
 * hands over to the conversation with leadership. Afterwards the same screen
 * edits the facts.
 */
export function CompanyOnboarding() {
  const token = useCompanyToken();
  const { session, setSession } = useAuth();
  const navigate = useNavigate();
  const [state, setState] = useState<OnboardingState | null>(null);
  const [answers, setAnswers] = useState<QuestionnaireAnswers>({});
  const [acknowledged, setAcknowledged] = useState(false);
  const [errors, setErrors] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [websiteUrl, setWebsiteUrl] = useState('');
  const [savingWebsite, setSavingWebsite] = useState(false);
  const [adminPhone, setAdminPhone] = useState('');
  const [adminName, setAdminName] = useState('');
  const [savingAccount, setSavingAccount] = useState(false);

  useEffect(() => {
    if (!token) return;
    api
      .companyOnboarding(token)
      .then((d) => {
        setState(d);
        setAnswers(withScopeDefaults(d));
        setAcknowledged(Boolean(d.engagement?.confidentiality_acknowledged_at));
        setWebsiteUrl(d.company.website_url || '');
        setAdminName(d.key_user.name || '');
        setAdminPhone(d.key_user.phone || '');
      })
      .catch(() => setErrors(['Could not load your company profile.']))
      .finally(() => setLoading(false));
  }, [token]);

  const autosave = useFormAutosave(token, answers, ONBOARDING_FIELDS);
  const submitted = Boolean(state?.submitted_at);

  const setAnswer = (id: string, value: AnswerValue) => {
    setAnswers((prev) => ({ ...prev, [id]: value }));
    autosave.notifyChange(id);
  };

  // P1 offers the client's own departments: those in the engagement's scope,
  // or else the ones named above.
  const departmentField = useMemo<QuestionnaireField>(() => {
    const base = ONBOARDING_FIELDS.find((f) => f.id === 'p1_departments')!;
    const engagement = state?.engagement;
    let options: string[];
    if (engagement?.scope_type === 'DEPARTMENT') {
      options = engagement.departments_in_scope;
    } else {
      const named = Array.isArray(answers.o06_departments) ? answers.o06_departments : [];
      options = [...named.filter((d) => d !== 'Other' && d !== NOT_SURE), ...splitList(answers[otherKey('o06_departments')])];
    }
    const chosen = Array.isArray(answers.p1_departments) ? answers.p1_departments : [];
    return { ...base, options: Array.from(new Set([...options, ...chosen])) };
  }, [answers, state?.engagement]);

  const saveWebsite = async () => {
    if (!token) return;
    setSavingWebsite(true);
    try {
      const res = await api.updateOnboardingProfile(token, { website_url: websiteUrl.trim() || null });
      setWebsiteUrl(res.website_url || '');
    } catch (err) {
      setErrors([err instanceof Error ? err.message : 'Could not save the website']);
    } finally {
      setSavingWebsite(false);
    }
  };

  const saveAccount = async () => {
    if (!token) return;
    setSavingAccount(true);
    try {
      const res = await api.updateCompanyMe(token, { name: adminName.trim() || undefined, phone: adminPhone.trim() || null });
      setAdminName(res.user.name || '');
      setAdminPhone(res.user.phone || '');
    } catch (err) {
      setErrors([err instanceof Error ? err.message : 'Could not save your details']);
    } finally {
      setSavingAccount(false);
    }
  };

  const submit = async () => {
    if (!token) return;
    setSubmitting(true);
    setErrors([]);
    try {
      await autosave.flush();
      const res = await api.submitOnboarding(token, { answers, confidentiality_acknowledged: acknowledged });
      setState(res);
      if (session?.portal === 'company' && !session.company.portal_onboarding_completed_at) {
        setSession({ ...session, company: { ...session.company, portal_onboarding_completed_at: new Date().toISOString() } });
      }
      if (!submitted) navigate('/company/dashboard', { replace: true });
    } catch (err) {
      setErrors([err instanceof Error ? err.message : 'Could not submit']);
    } finally {
      setSubmitting(false);
    }
  };

  if (loading) {
    return (
      <div className="space-y-6">
        <Skeleton variant="text" />
        <Skeleton variant="card" />
      </div>
    );
  }

  return (
    <div className="mx-auto flex max-w-3xl flex-col gap-4 pb-12">
      <div className="sticky top-0 z-20 -mx-1 bg-background/95 px-1 py-3 backdrop-blur supports-[backdrop-filter]:bg-background/80">
        <PageHeader
          title="Company profile"
          description={
            submitted
              ? 'The facts about your company we work from. Change anything that has moved on.'
              : 'About five minutes. These are facts only — pick “Not sure” for anything you don’t know, and we’ll cover the rest when we talk.'
          }
        />
        <p aria-live="polite" className="m-0 h-4 text-right text-xs text-muted-foreground">
          {autosave.status === 'saving' && 'Saving…'}
          {autosave.status === 'saved' && 'Saved'}
          {autosave.status === 'error' && <span className="text-status-error">Not saved</span>}
        </p>
      </div>

      <Card className="space-y-3 p-4 sm:p-5">
        <h2 className="m-0 text-base font-medium text-foreground">You</h2>
        <div className="grid gap-3 sm:grid-cols-2">
          <Input label="Your name" value={adminName} onChange={(e) => setAdminName(e.target.value)} />
          <Input
            label="Your phone"
            type="tel"
            value={adminPhone}
            onChange={(e) => setAdminPhone(e.target.value)}
            placeholder="+971 50 000 0000"
          />
        </div>
        <Button type="button" variant="secondary" size="sm" loading={savingAccount} onClick={saveAccount}>
          Save your details
        </Button>
      </Card>

      <Card className="space-y-3 p-4 sm:p-5">
        <h2 className="m-0 text-base font-medium text-foreground">Company website</h2>
        <div className="flex flex-col gap-3 sm:flex-row sm:items-end">
          <div className="min-w-0 flex-1">
            <Input label="Website" value={websiteUrl} onChange={(e) => setWebsiteUrl(e.target.value)} placeholder="company.com" />
          </div>
          <Button type="button" variant="secondary" size="sm" loading={savingWebsite} onClick={saveWebsite}>
            Save website
          </Button>
        </div>
      </Card>

      {ONBOARDING_GROUPS.map((group) => (
        <Card key={group.id} className="space-y-6 p-4 sm:p-6">
          <div>
            <h2 className="m-0 text-lg font-medium text-foreground">{group.title}</h2>
            {group.intro && <p className="m-0 mt-1 text-sm text-muted-foreground">{group.intro}</p>}
          </div>
          {group.fields.map((field) => (
            <FieldRenderer
              key={field.id}
              field={field.id === 'p1_departments' ? departmentField : field}
              answers={answers}
              setAnswer={setAnswer}
            />
          ))}
          {group.id === 3 && (
            <p className="m-0 text-sm text-muted-foreground">
              Optional: an organisation chart, a staff or system list, or process and policy documents help us ask
              fewer questions later. <Link to="/company/documents">Upload documents</Link>
            </p>
          )}
        </Card>
      ))}

      <Card className="space-y-4 p-4 sm:p-6">
        <label className="flex items-start gap-3 text-sm text-foreground">
          <input
            type="checkbox"
            className="mt-1"
            checked={acknowledged}
            disabled={Boolean(state?.engagement?.confidentiality_acknowledged_at)}
            onChange={(e) => setAcknowledged(e.target.checked)}
          />
          <span>{state?.confidentiality.text}</span>
        </label>

        {errors.length > 0 && (
          <ul className="m-0 list-disc space-y-1 pl-5 text-sm text-status-error">
            {errors.map((e) => (
              <li key={e}>{e}</li>
            ))}
          </ul>
        )}

        <div className="flex justify-end">
          <Button loading={submitting} onClick={submit}>
            {submitted ? 'Save changes' : 'Submit'}
          </Button>
        </div>
      </Card>
    </div>
  );
}

/**
 * A department-scoped engagement starts with its departments already chosen to
 * take part (Doc 07 §7, P1: "pre-selected from engagement scope").
 */
function withScopeDefaults(state: OnboardingState): QuestionnaireAnswers {
  const answers = { ...(state.answers as QuestionnaireAnswers) };
  const scope = state.engagement;
  if (!answers.p1_departments && scope?.scope_type === 'DEPARTMENT' && scope.departments_in_scope.length > 0) {
    answers.p1_departments = [...scope.departments_in_scope];
  }
  return answers;
}
