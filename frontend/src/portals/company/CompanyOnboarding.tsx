import { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Check, ChevronLeft, ChevronRight } from 'lucide-react';
import { api } from '../../lib/api';
import { useCompanyToken, useAuth } from '../../lib/auth';
import { PageHeader, Card, Input, Button, Skeleton, ProgressBar } from '../../components/ui';
import { useMediaQuery } from '../../lib/useMediaQuery';
import {
  QUESTIONNAIRE_STEPS,
  STEP_COUNT,
  computeCompletionPercent,
  stepComplete,
  stepTouched,
  type AnswerValue,
  type QuestionnaireAnswers,
} from '../../lib/questionnaireOptions';
import { FieldRenderer } from './questionnaire/FieldRenderer';
import { useQuestionnaireAutosave } from './useQuestionnaireAutosave';
import { cn } from '../../lib/cn';

export function CompanyOnboarding() {
  const token = useCompanyToken();
  const { session, setSession } = useAuth();
  const navigate = useNavigate();
  const isNarrow = useMediaQuery('(max-width: 1023px)');
  const [sectionId, setSectionId] = useState(1);
  const [answers, setAnswers] = useState<QuestionnaireAnswers>({});
  const [percent, setPercent] = useState(0);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [finishing, setFinishing] = useState(false);
  const [websiteUrl, setWebsiteUrl] = useState('');
  const [displayName, setDisplayName] = useState('');
  const [locale, setLocale] = useState('en');
  const [savingWebsite, setSavingWebsite] = useState(false);
  const [adminPhone, setAdminPhone] = useState('');
  const [adminName, setAdminName] = useState('');
  const [savingAccount, setSavingAccount] = useState(false);

  useEffect(() => {
    if (!token) return;
    api
      .companyOnboarding(token)
      .then((d) => {
        setAnswers((d.questionnaire_answers || {}) as QuestionnaireAnswers);
        setSectionId(d.step || 1);
        setPercent(d.completion_percent ?? computeCompletionPercent((d.questionnaire_answers || {}) as QuestionnaireAnswers));
        setWebsiteUrl(d.company?.website_url || '');
        setDisplayName(d.company?.display_name || '');
        setLocale(d.company?.locale || 'en');
      })
      .catch(() => setError('Could not load questionnaire.'))
      .finally(() => setLoading(false));
    api
      .companyMe(token)
      .then((d) => {
        setAdminPhone(d.user.phone || '');
        setAdminName(d.user.name || '');
      })
      .catch(() => undefined);
  }, [token]);

  const section = useMemo(
    () => QUESTIONNAIRE_STEPS.find((s) => s.id === sectionId) || QUESTIONNAIRE_STEPS[0],
    [sectionId]
  );

  const autosave = useQuestionnaireAutosave(token, answers, QUESTIONNAIRE_STEPS);

  const setAnswer = (id: string, value: AnswerValue) => {
    setAnswers((prev) => {
      const next = { ...prev, [id]: value };
      setPercent(computeCompletionPercent(next));
      return next;
    });
    autosave.notifyChange(id);
  };

  const persist = async (nextSection?: number, opts?: { markComplete?: boolean }) => {
    if (!token) return;
    setSaving(true);
    setError('');
    try {
      await autosave.flush();
      const cleaned: QuestionnaireAnswers = {};
      Object.entries(answers).forEach(([k, v]) => {
        cleaned[k] = v;
      });
      const res = await api.updateOnboardingQuestionnaire(token, {
        questionnaire_answers: cleaned,
        questionnaire_step: nextSection ?? sectionId,
      });
      setPercent(res.completion_percent);
      if (nextSection) setSectionId(nextSection);
      if (opts?.markComplete) {
        await finish(true);
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not save');
    } finally {
      setSaving(false);
    }
  };

  const jumpTo = async (id: number) => {
    await persist(id);
  };

  const saveWebsite = async () => {
    if (!token) return;
    setSavingWebsite(true);
    setError('');
    try {
      const res = await api.updateOnboardingProfile(token, {
        display_name: displayName || (session?.portal === 'company' ? session.company?.name : undefined) || 'Company',
        locale,
        website_url: websiteUrl.trim() || null,
      });
      if (res.website_url !== undefined) setWebsiteUrl(res.website_url || '');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not save website');
    } finally {
      setSavingWebsite(false);
    }
  };

  const saveAccount = async () => {
    if (!token) return;
    setSavingAccount(true);
    setError('');
    try {
      const res = await api.updateCompanyMe(token, {
        name: adminName.trim() || undefined,
        phone: adminPhone.trim() || null,
      });
      setAdminPhone(res.user.phone || '');
      setAdminName(res.user.name || '');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not save account details');
    } finally {
      setSavingAccount(false);
    }
  };

  const finish = async (markQuestionnaireComplete = false) => {
    if (!token) return;
    setFinishing(true);
    setError('');
    try {
      await api.updateOnboardingQuestionnaire(token, {
        questionnaire_answers: answers,
        questionnaire_step: sectionId,
      });
      await api.completeOnboarding(token, {
        mark_questionnaire_complete: markQuestionnaireComplete || percent >= 100,
      });
      if (session?.portal === 'company') {
        setSession({
          ...session,
          company: {
            ...session.company,
            portal_onboarding_completed_at: new Date().toISOString(),
          },
        });
      }
      navigate('/company/dashboard', { replace: true });
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not finish setup');
    } finally {
      setFinishing(false);
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

  const sectionNav = (
    <nav className={cn(isNarrow ? 'flex gap-2 overflow-x-auto pb-1' : 'space-y-1')} aria-label="Questionnaire steps">
      {QUESTIONNAIRE_STEPS.map((s) => {
        const touched = stepTouched(s.id, answers);
        const done = stepComplete(s.id, answers);
        const active = s.id === sectionId;
        return (
          <button
            key={s.id}
            type="button"
            onClick={() => jumpTo(s.id)}
            className={cn(
              'flex shrink-0 items-center gap-2 rounded-lg px-3 py-2 text-sm transition-colors',
              isNarrow ? 'whitespace-nowrap border' : 'w-full text-left',
              active
                ? 'border-primary bg-primary text-primary-foreground'
                : 'border-border text-muted-foreground hover:bg-muted/50 hover:text-foreground'
            )}
          >
            <span
              className={cn(
                'flex h-5 w-5 items-center justify-center rounded-full text-[10px]',
                active
                  ? 'bg-primary-foreground/20'
                  : done
                    ? 'bg-primary/15 text-primary'
                    : touched
                      ? 'bg-primary/5 text-primary'
                      : 'bg-muted'
              )}
            >
              {done ? <Check className="h-3 w-3" /> : s.id}
            </span>
            {isNarrow ? s.shortTitle : s.title}
          </button>
        );
      })}
    </nav>
  );

  return (
    <div className="mx-auto flex min-h-[70vh] max-w-5xl flex-col gap-4 pb-28 lg:pb-8">
      <div className="sticky top-0 z-20 -mx-1 space-y-3 bg-background/95 px-1 py-3 backdrop-blur supports-[backdrop-filter]:bg-background/80">
        <PageHeader
          title="Company profile"
          description="Your answers save as you go. The percentage tracks the essential questions only — the rest are worth answering, never required."
        />
        <div className="flex items-center gap-3">
          <div className="min-w-0 flex-1">
            <ProgressBar value={percent} />
          </div>
          <span className="shrink-0 text-sm font-semibold tabular-nums text-foreground">{percent}%</span>
          {/* Reserves its own width so the bar does not jump as the text changes. */}
          <span
            aria-live="polite"
            className="w-16 shrink-0 text-right text-xs text-muted-foreground"
          >
            {autosave.status === 'saving' && 'Saving…'}
            {autosave.status === 'saved' && 'Saved'}
            {autosave.status === 'error' && <span className="text-status-error">Not saved</span>}
          </span>
        </div>
        {isNarrow ? sectionNav : null}
      </div>

      {error ? <p className="text-sm text-status-error">{error}</p> : null}

      <Card className="space-y-3 p-4 sm:p-5">
        <div>
          <h2 className="m-0 text-base font-medium text-foreground">Your account</h2>
          <p className="m-0 mt-1 text-sm text-muted-foreground">
            Update the name and phone number used for your company admin login.
          </p>
        </div>
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
        <Button type="button" variant="secondary" loading={savingAccount} onClick={saveAccount}>
          Save account
        </Button>
      </Card>

      <Card className="space-y-3 p-4 sm:p-5">
        <div>
          <h2 className="m-0 text-base font-medium text-foreground">Company website</h2>
          <p className="m-0 mt-1 text-sm text-muted-foreground">
            Used by discovery agents and optional website research for reports.
          </p>
        </div>
        <div className="flex flex-col gap-3 sm:flex-row sm:items-end">
          <div className="min-w-0 flex-1">
            <Input
              label="Website URL"
              value={websiteUrl}
              onChange={(e) => setWebsiteUrl(e.target.value)}
              placeholder="https://example.com"
            />
          </div>
          <Button type="button" variant="secondary" loading={savingWebsite} onClick={saveWebsite}>
            Save website
          </Button>
        </div>
      </Card>

      <div className="grid gap-4 lg:grid-cols-[220px_1fr]">
        {!isNarrow ? (
          <aside className="lg:sticky lg:top-36 lg:self-start">
            <Card className="p-2">{sectionNav}</Card>
          </aside>
        ) : null}

        <Card className="space-y-6 p-4 sm:p-6">
          <div>
            <p className="m-0 text-xs font-medium uppercase tracking-wide text-muted-foreground">
              Step {section.id} of {STEP_COUNT}
            </p>
            <h2 className="m-0 mt-1 text-xl font-medium text-foreground">{section.title}</h2>
          </div>

          <div className="space-y-8">
            {section.screens.map((screen) => (
              <div key={screen.id} className="space-y-6">
                {screen.fields.map((field) => (
                  <FieldRenderer
                    key={field.id}
                    field={field}
                    answers={answers}
                    setAnswer={setAnswer}
                  />
                ))}
              </div>
            ))}
          </div>

          <div className="hidden flex-wrap gap-2 border-t border-border pt-4 lg:flex">
            <Button
              variant="secondary"
              disabled={sectionId <= 1 || saving}
              onClick={() => jumpTo(sectionId - 1)}
            >
              <ChevronLeft className="mr-1 h-4 w-4" />
              Back
            </Button>
            {sectionId < STEP_COUNT ? (
              <Button loading={saving} onClick={() => persist(sectionId + 1)}>
                Save & continue
                <ChevronRight className="ml-1 h-4 w-4" />
              </Button>
            ) : (
              <Button loading={finishing || saving} onClick={() => persist(STEP_COUNT, { markComplete: true })}>
                Finish profile
              </Button>
            )}
            <Button variant="secondary" loading={finishing} onClick={() => finish(false)}>
              Skip for now
            </Button>
          </div>
        </Card>
      </div>

      <div className="fixed inset-x-0 bottom-0 z-30 border-t border-border bg-background/95 p-3 backdrop-blur lg:hidden">
        <div className="mx-auto flex max-w-5xl flex-wrap gap-2">
          <Button
            size="sm"
            variant="secondary"
            className="flex-1"
            disabled={sectionId <= 1 || saving}
            onClick={() => jumpTo(sectionId - 1)}
          >
            Back
          </Button>
          {sectionId < STEP_COUNT ? (
            <Button size="sm" className="flex-[2]" loading={saving} onClick={() => persist(sectionId + 1)}>
              Save & continue
            </Button>
          ) : (
            <Button
              size="sm"
              className="flex-[2]"
              loading={finishing || saving}
              onClick={() => persist(STEP_COUNT, { markComplete: true })}
            >
              Finish
            </Button>
          )}
          <Button size="sm" variant="secondary" loading={finishing} onClick={() => finish(false)}>
            Skip
          </Button>
        </div>
      </div>
    </div>
  );
}
