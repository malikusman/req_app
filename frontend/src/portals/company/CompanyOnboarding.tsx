import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { useNavigate } from 'react-router-dom';
import { Check, ChevronLeft, ChevronRight, Loader2 } from 'lucide-react';
import { api } from '../../lib/api';
import { useCompanyToken, useAuth } from '../../lib/auth';
import { PageHeader, Card, Input, Button, Textarea, Skeleton, ProgressBar } from '../../components/ui';
import { Sheet, SheetContent, SheetHeader, SheetTitle } from '@/components/shadcn/sheet';
import { useMediaQuery } from '../../lib/useMediaQuery';
import {
  computeCompletionPercent,
  fieldIsVisible,
  sectionTouched,
  type FieldTier,
  type QuestionnaireAnswers,
  type QuestionnaireField,
} from '../../lib/questionnaireOptions';
import { questionnaireSectionsFor } from '../../lib/questionnaireV2Config';
import { cn } from '../../lib/cn';
import { useQuestionnaireAutosave, type AutosaveStatus } from './useQuestionnaireAutosave';

function AutosaveIndicator({ status, className }: { status: AutosaveStatus; className?: string }) {
  return (
    <div className={cn('flex h-5 items-center gap-1.5 text-xs', className)} aria-live="polite">
      {status === 'saving' ? (
        <>
          <Loader2 className="h-3.5 w-3.5 animate-spin text-muted-foreground" />
          <span className="text-muted-foreground">Saving…</span>
        </>
      ) : status === 'saved' ? (
        <>
          <Check className="h-3.5 w-3.5 text-status-success" />
          <span className="text-status-success">Saved</span>
        </>
      ) : status === 'error' ? (
        <span className="text-status-error">Couldn't save</span>
      ) : null}
    </div>
  );
}

function TierTag({ tier }: { tier?: FieldTier }) {
  if (tier === 'recommended' || tier === 'optional' || tier === 'essential') {
    const label = tier === 'recommended' ? 'Recommended' : tier === 'optional' ? 'Optional' : 'Essential';
    return <span className="ml-1.5 text-xs font-normal text-muted-foreground">{label}</span>;
  }
  return null; // no explicit tier (all v1 fields) or 'conditional' → no tag
}

function ChoiceButton({
  active,
  onClick,
  children,
}: {
  active: boolean;
  onClick: () => void;
  children: ReactNode;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        'min-h-11 w-full rounded-lg border px-3 py-2.5 text-left text-sm transition-colors',
        active
          ? 'border-primary bg-primary/10 text-foreground'
          : 'border-border text-muted-foreground hover:border-primary/40 hover:bg-muted/40'
      )}
    >
      {children}
    </button>
  );
}

function SearchableSelectField({
  field,
  value,
  onChange,
  isNarrow,
}: {
  field: QuestionnaireField;
  value: string;
  onChange: (v: string) => void;
  isNarrow: boolean;
}) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');
  const options = field.options || [];
  const filtered = options.filter((o) => o.toLowerCase().includes(query.toLowerCase()));

  const pick = (opt: string) => {
    onChange(opt);
    setOpen(false);
    setQuery('');
  };

  const list = (
    <div className="space-y-2">
      <Input
        label="Search"
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        placeholder="Type to filter…"
        autoFocus
      />
      <ul className="max-h-64 space-y-1 overflow-y-auto">
        {filtered.map((opt) => (
          <li key={opt}>
            <ChoiceButton active={value === opt} onClick={() => pick(opt)}>
              {opt}
            </ChoiceButton>
          </li>
        ))}
        {filtered.length === 0 ? <li className="text-sm text-muted-foreground">No matches</li> : null}
      </ul>
    </div>
  );

  if (isNarrow) {
    return (
      <div className="space-y-2">
        <p className="m-0 text-sm font-medium text-foreground">
          {field.label}
          <TierTag tier={field.tier} />
        </p>
        <Button type="button" variant="secondary" className="w-full justify-between" onClick={() => setOpen(true)}>
          <span className="truncate">{value || 'Select…'}</span>
          <ChevronRight className="h-4 w-4 shrink-0 opacity-50" />
        </Button>
        <Sheet open={open} onOpenChange={setOpen}>
          <SheetContent side="bottom" className="max-h-[85dvh] overflow-y-auto">
            <SheetHeader>
              <SheetTitle>{field.label}</SheetTitle>
            </SheetHeader>
            <div className="mt-4">{list}</div>
          </SheetContent>
        </Sheet>
      </div>
    );
  }

  return (
    <div className="space-y-2">
      <p className="m-0 text-sm font-medium text-foreground">
        {field.label}
        <TierTag tier={field.tier} />
      </p>
      <Button type="button" variant="secondary" className="w-full justify-between" onClick={() => setOpen(!open)}>
        <span className="truncate">{value || 'Select…'}</span>
      </Button>
      {open ? <Card className="p-3">{list}</Card> : null}
    </div>
  );
}

function FieldEditor({
  field,
  answers,
  setAnswer,
  isNarrow,
}: {
  field: QuestionnaireField;
  answers: QuestionnaireAnswers;
  setAnswer: (id: string, value: string | string[] | undefined) => void;
  isNarrow: boolean;
}) {
  if (!fieldIsVisible(field, answers)) return null;
  const raw = answers[field.id];

  let content: ReactNode;

  if (field.type === 'text') {
    content = (
      <Input
        label={
          <>
            {field.label}
            <TierTag tier={field.tier} />
          </>
        }
        value={typeof raw === 'string' ? raw : ''}
        onChange={(e) => setAnswer(field.id, e.target.value)}
        placeholder={field.placeholder}
      />
    );
  } else if (field.type === 'textarea') {
    content = (
      <Textarea
        label={
          <>
            {field.label}
            <TierTag tier={field.tier} />
          </>
        }
        rows={4}
        value={typeof raw === 'string' ? raw : ''}
        onChange={(e) => setAnswer(field.id, e.target.value)}
        placeholder={field.placeholder}
      />
    );
  } else if (field.type === 'searchable_select') {
    content = (
      <SearchableSelectField
        field={field}
        value={typeof raw === 'string' ? raw : ''}
        onChange={(v) => setAnswer(field.id, v)}
        isNarrow={isNarrow}
      />
    );
  } else if (field.type === 'single_select') {
    const value = typeof raw === 'string' ? raw : '';
    content = (
      <fieldset className="space-y-2">
        <legend className="text-sm font-medium text-foreground">
          {field.label}
          <TierTag tier={field.tier} />
        </legend>
        <div className="grid gap-2 sm:grid-cols-2">
          {(field.options || []).map((opt) => (
            <ChoiceButton key={opt} active={value === opt} onClick={() => setAnswer(field.id, opt)}>
              {opt}
            </ChoiceButton>
          ))}
        </div>
      </fieldset>
    );
  } else if (field.type === 'static') {
    content = <p className="text-sm text-muted-foreground">{field.label}</p>;
  } else {
    // multi_select
    const selected = Array.isArray(raw) ? raw : [];
    const toggle = (opt: string) => {
      if (selected.includes(opt)) {
        setAnswer(
          field.id,
          selected.filter((s) => s !== opt)
        );
        return;
      }
      if (field.maxSelections && selected.length >= field.maxSelections) return;
      setAnswer(field.id, [...selected, opt]);
    };

    const hasGroups = field.groups && field.groups.length > 0;

    content = (
      <fieldset className="space-y-2">
        <legend className="text-sm font-medium text-foreground">
          {field.label}
          <TierTag tier={field.tier} />
        </legend>
        {hasGroups ? (
          <div className="space-y-3">
            {field.groups!.map((group, gi) => (
              <div key={group.label || gi} className="space-y-2">
                {group.label ? (
                  <p className="text-sm font-medium text-muted-foreground">{group.label}</p>
                ) : null}
                <div className="grid gap-2 sm:grid-cols-2">
                  {group.options.map((opt) => (
                    <ChoiceButton key={opt} active={selected.includes(opt)} onClick={() => toggle(opt)}>
                      {opt}
                    </ChoiceButton>
                  ))}
                </div>
              </div>
            ))}
          </div>
        ) : (
          <div className="grid gap-2 sm:grid-cols-2">
            {(field.options || []).map((opt) => (
              <ChoiceButton key={opt} active={selected.includes(opt)} onClick={() => toggle(opt)}>
                {opt}
              </ChoiceButton>
            ))}
          </div>
        )}
      </fieldset>
    );
  }

  if (field.helper) {
    return (
      <div className="space-y-1">
        {content}
        <p className="text-xs text-muted-foreground">{field.helper}</p>
      </div>
    );
  }

  return content;
}

export function CompanyOnboarding() {
  const token = useCompanyToken();
  const { session, setSession } = useAuth();
  const navigate = useNavigate();
  const isNarrow = useMediaQuery('(max-width: 1023px)');
  const [sectionId, setSectionId] = useState(1);
  const [questionnaireVersion, setQuestionnaireVersion] = useState(1);
  const navigatedRef = useRef(false);
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
        setQuestionnaireVersion(d.questionnaire_version ?? 1);
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

  useEffect(() => {
    if (!navigatedRef.current) return;
    navigatedRef.current = false;
    const heading = document.getElementById('questionnaire-section-heading');
    if (!heading) return;
    const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    heading.scrollIntoView({ behavior: reduced ? 'auto' : 'smooth', block: 'start' });
    heading.focus({ preventScroll: true });
  }, [sectionId]);

  const sections = useMemo(() => questionnaireSectionsFor(questionnaireVersion), [questionnaireVersion]);

  const section = useMemo(
    () => sections.find((s) => s.id === sectionId) || sections[0],
    [sections, sectionId]
  );

  const autosave = useQuestionnaireAutosave(token, answers, sections, questionnaireVersion >= 2);

  const setAnswer = (id: string, value: string | string[] | undefined) => {
    setAnswers((prev) => {
      const next = { ...prev, [id]: value };
      setPercent(computeCompletionPercent(next, sections));
      return next;
    });
    autosave.notifyChange(id);
  };

  const changeSection = (nextSection: number) => {
    navigatedRef.current = true;
    setSectionId(nextSection);
  };

  const persist = async (nextSection?: number, opts?: { markComplete?: boolean }) => {
    if (!token) return;
    await autosave.flush();
    setSaving(true);
    setError('');
    try {
      const cleaned: Record<string, string | string[] | undefined> = {};
      Object.entries(answers).forEach(([k, v]) => {
        cleaned[k] = v;
      });
      const res = await api.updateOnboardingQuestionnaire(token, {
        questionnaire_answers: cleaned,
        questionnaire_step: nextSection ?? sectionId,
      });
      setPercent(res.completion_percent);
      if (nextSection) changeSection(nextSection);
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
    await autosave.flush();
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
    <nav className={cn(isNarrow ? 'flex gap-2 overflow-x-auto pb-1' : 'space-y-1')} aria-label="Questionnaire sections">
      {sections.map((s) => {
        const touched = sectionTouched(s.id, answers, sections);
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
                active ? 'bg-primary-foreground/20' : touched ? 'bg-primary/15 text-primary' : 'bg-muted'
              )}
            >
              {touched ? <Check className="h-3 w-3" /> : s.id}
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
          title="Profile"
          description={
            questionnaireVersion >= 2
              ? 'This profile helps Worktruth understand your business and analyze it more accurately. Fields marked Essential are required to complete your profile — Recommended and Optional fields are up to you.'
              : 'This profile helps Worktruth understand your business and analyze it more accurately. Nothing is required — fill what you can.'
          }
        />
        <div className="flex items-center gap-3">
          <div className="min-w-0 flex-1">
            <ProgressBar value={percent} />
          </div>
          <span className="shrink-0 text-sm font-semibold tabular-nums text-foreground">{percent}%</span>
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
              {questionnaireVersion >= 2 ? 'Step' : 'Section'} {section.id} of {sections.length}
            </p>
            <h2
              id="questionnaire-section-heading"
              tabIndex={-1}
              className="m-0 mt-1 scroll-mt-36 text-xl font-medium text-foreground outline-none"
            >
              {section.title}
            </h2>
          </div>

          <div className="space-y-6">
            {section.fields.map((field) => (
              <FieldEditor
                key={field.id}
                field={field}
                answers={answers}
                setAnswer={setAnswer}
                isNarrow={isNarrow}
              />
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
            {sectionId < sections.length ? (
              <Button loading={saving} onClick={() => persist(sectionId + 1)}>
                {questionnaireVersion >= 2 ? 'Continue' : 'Save & continue'}
                <ChevronRight className="ml-1 h-4 w-4" />
              </Button>
            ) : (
              <Button loading={finishing || saving} onClick={() => persist(sections.length, { markComplete: true })}>
                Finish profile
              </Button>
            )}
            <Button variant="secondary" loading={finishing} onClick={() => finish(false)}>
              Skip for now
            </Button>
            {questionnaireVersion >= 2 ? (
              <AutosaveIndicator status={autosave.status} className="ml-auto min-w-[96px] justify-end" />
            ) : null}
          </div>
        </Card>
      </div>

      <div className="fixed inset-x-0 bottom-0 z-30 border-t border-border bg-background/95 p-3 backdrop-blur lg:hidden">
        <div className="mx-auto max-w-5xl">
          {questionnaireVersion >= 2 ? (
            <AutosaveIndicator status={autosave.status} className="mb-1.5 w-full justify-end" />
          ) : null}
          <div className="flex flex-wrap gap-2">
            <Button
              size="sm"
              variant="secondary"
              className="flex-1"
              disabled={sectionId <= 1 || saving}
              onClick={() => jumpTo(sectionId - 1)}
            >
              Back
            </Button>
            {sectionId < sections.length ? (
              <Button size="sm" className="flex-[2]" loading={saving} onClick={() => persist(sectionId + 1)}>
                {questionnaireVersion >= 2 ? 'Continue' : 'Save & continue'}
              </Button>
            ) : (
              <Button
                size="sm"
                className="flex-[2]"
                loading={finishing || saving}
                onClick={() => persist(sections.length, { markComplete: true })}
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
    </div>
  );
}
