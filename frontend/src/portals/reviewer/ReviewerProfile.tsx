import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { Check, ChevronLeft, ChevronRight, Eye, ShieldCheck } from 'lucide-react';
import { api, type ReviewerExperience, type ReviewerProfile, type ReviewerPublicCard } from '../../lib/api';
import { useReviewerToken } from '../../lib/auth';
import {
  PageHeader,
  Card,
  Button,
  Input,
  Textarea,
  Badge,
  Skeleton,
  ProgressBar,
  Modal,
  useToast,
} from '../../components/ui';
import { ExpertReviewerCard } from '../../components/ExpertReviewerCard';
import { Sheet, SheetContent, SheetHeader, SheetTitle } from '@/components/shadcn/sheet';
import { useMediaQuery } from '../../lib/useMediaQuery';
import { cn } from '../../lib/cn';
import {
  REVIEWER_QUESTIONNAIRE_SECTIONS,
  computeReviewerCompletionPercent,
  reviewerSectionTouched,
  type ReviewerAnswers,
  type ReviewerQuestionnaireField,
} from '../../lib/reviewerQuestionnaireOptions';

const YEARS_BAND_MIDPOINT: Record<string, number> = {
  '<3 years': 2,
  '3–7 years': 5,
  '8–15 years': 11,
  '16–25 years': 20,
  '25+ years': 28,
};

const emptyExperience = (): ReviewerExperience => ({
  organization: '',
  title: '',
  start_year: new Date().getFullYear() - 5,
  end_year: null,
  summary: '',
});

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
  field: ReviewerQuestionnaireField;
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
      <Input label="Search" value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Type to filter…" autoFocus />
      <ul className="max-h-64 space-y-1 overflow-y-auto">
        {filtered.map((opt) => (
          <li key={opt}>
            <ChoiceButton active={value === opt} onClick={() => pick(opt)}>
              {opt}
            </ChoiceButton>
          </li>
        ))}
      </ul>
    </div>
  );

  if (isNarrow) {
    return (
      <div className="space-y-2">
        <p className="m-0 text-sm font-medium text-foreground">{field.label}</p>
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
      <p className="m-0 text-sm font-medium text-foreground">{field.label}</p>
      <Button type="button" variant="secondary" className="w-full justify-between" onClick={() => setOpen(!open)}>
        <span className="truncate">{value || 'Select…'}</span>
      </Button>
      {open ? <Card className="p-3">{list}</Card> : null}
    </div>
  );
}

export function ReviewerProfile() {
  const token = useReviewerToken();
  const { toast } = useToast();
  const isNarrow = useMediaQuery('(max-width: 1023px)');
  const avatarRef = useRef<HTMLInputElement>(null);
  const cvRef = useRef<HTMLInputElement>(null);

  const [profile, setProfile] = useState<ReviewerProfile | null>(null);
  const [sectionId, setSectionId] = useState(1);
  const [answers, setAnswers] = useState<ReviewerAnswers>({});
  const [percent, setPercent] = useState(0);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [publishing, setPublishing] = useState(false);
  const [avatarPreview, setAvatarPreview] = useState<string | null>(null);
  const [previewOpen, setPreviewOpen] = useState(false);

  const extras = useMemo(
    () => ({
      hasAvatar: Boolean(profile?.avatar_url),
      hasCv: Boolean(profile?.has_cv),
      hasExperiences: (profile?.experiences?.length || 0) > 0,
    }),
    [profile]
  );

  const hydrateFromProfile = (d: Awaited<ReturnType<typeof api.reviewerProfile>>) => {
    setProfile(d.profile);
    const qa = (d.questionnaire_answers || {}) as ReviewerAnswers;
    const yearsBand =
      typeof qa.years_experience === 'string'
        ? qa.years_experience
        : d.profile.years_experience != null
          ? Object.entries({ 2: '<3 years', 5: '3–7 years', 11: '8–15 years', 20: '16–25 years', 28: '25+ years' }).find(
              ([n]) => Math.abs(Number(n) - (d.profile.years_experience || 0)) <= 3
            )?.[1]
          : undefined;

    const merged: ReviewerAnswers = {
      name: d.user.name,
      email: d.user.email,
      headline: qa.headline ?? d.profile.headline ?? '',
      bio: qa.bio ?? d.profile.bio ?? '',
      linkedin_url: qa.linkedin_url ?? d.profile.linkedin_url ?? '',
      website: qa.website ?? d.profile.website_url ?? '',
      location: qa.location ?? d.profile.location ?? '',
      years_experience: yearsBand,
      strengths: (qa.strengths as string[]) ?? d.profile.expertise_tags ?? [],
      industries_covered: (qa.industries_covered as string[]) ?? d.profile.industries ?? [],
      experiences:
        (qa.experiences as ReviewerExperience[])?.length
          ? (qa.experiences as ReviewerExperience[])
          : d.profile.experiences.length
            ? d.profile.experiences
            : [emptyExperience()],
      career_background: qa.career_background,
      seniority_level: qa.seniority_level,
      team_size_managed: qa.team_size_managed,
      education_level: qa.education_level,
      field_of_study: qa.field_of_study,
      certifications: qa.certifications,
      company_size_familiarity: qa.company_size_familiarity,
      regional_expertise: qa.regional_expertise,
      review_focus: qa.review_focus,
      ai_fluency_level: qa.ai_fluency_level,
      ai_tools_familiarity: qa.ai_tools_familiarity,
      review_capacity: qa.review_capacity,
      engagement_type: qa.engagement_type,
      preferred_company_types: qa.preferred_company_types,
      cv_upload: qa.cv_upload ?? d.profile.has_cv,
    };
    setAnswers(merged);
    setSectionId(d.questionnaire_step || 1);
    setPercent(
      d.completion_percent ??
        computeReviewerCompletionPercent(merged, {
          hasAvatar: Boolean(d.profile.avatar_url),
          hasCv: Boolean(d.profile.has_cv),
          hasExperiences: d.profile.experiences.length > 0,
        })
    );
  };

  useEffect(() => {
    if (!token) return;
    api
      .reviewerProfile(token)
      .then(hydrateFromProfile)
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load profile'))
      .finally(() => setLoading(false));
  }, [token]);

  useEffect(() => {
    if (!token || !profile?.avatar_url) {
      setAvatarPreview(null);
      return;
    }
    let cancelled = false;
    let objectUrl: string | null = null;
    api
      .fetchReviewerAvatarPreview(token, profile.avatar_url)
      .then((url) => {
        if (cancelled) {
          URL.revokeObjectURL(url);
          return;
        }
        objectUrl = url;
        setAvatarPreview(url);
      })
      .catch(() => {
        /* keep any local object-URL preview from a fresh upload */
      });
    return () => {
      cancelled = true;
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [token, profile?.avatar_url]);

  const setAnswer = (id: string, value: unknown) => {
    setAnswers((prev) => {
      const next = { ...prev, [id]: value as ReviewerAnswers[string] };
      setPercent(computeReviewerCompletionPercent(next, extras));
      return next;
    });
  };

  const section = useMemo(
    () => REVIEWER_QUESTIONNAIRE_SECTIONS.find((s) => s.id === sectionId) || REVIEWER_QUESTIONNAIRE_SECTIONS[0],
    [sectionId]
  );

  const isPublished = profile?.profile_status === 'published';

  const companyPreview = useMemo((): ReviewerPublicCard => {
    const expRows = (
      Array.isArray(answers.experiences) ? (answers.experiences as ReviewerExperience[]) : profile?.experiences || []
    ).filter((e) => e.organization?.trim() && e.title?.trim());

    const yearsBand = typeof answers.years_experience === 'string' ? answers.years_experience : '';
    const years =
      (yearsBand && YEARS_BAND_MIDPOINT[yearsBand]) ||
      profile?.years_experience ||
      null;

    return {
      id: 0,
      name: (typeof answers.name === 'string' && answers.name.trim()) || 'Your name',
      headline: (typeof answers.headline === 'string' && answers.headline.trim()) || profile?.headline || null,
      bio: (typeof answers.bio === 'string' && answers.bio.trim()) || profile?.bio || null,
      avatar_url: profile?.avatar_url || null,
      expertise_tags: (Array.isArray(answers.strengths) ? (answers.strengths as string[]) : null) ||
        profile?.expertise_tags ||
        [],
      industries:
        (Array.isArray(answers.industries_covered) ? (answers.industries_covered as string[]) : null) ||
        profile?.industries ||
        [],
      years_experience: years,
      languages: profile?.languages || [],
      location: (typeof answers.location === 'string' && answers.location.trim()) || profile?.location || null,
      linkedin_url:
        (typeof answers.linkedin_url === 'string' && answers.linkedin_url.trim()) || profile?.linkedin_url || null,
      profile_status: profile?.profile_status || 'draft',
      platform_verified: Boolean(profile?.platform_verified_at),
      experiences: expRows,
    };
  }, [answers, profile]);

  const persist = async (nextSection?: number, opts?: { quiet?: boolean }) => {
    if (!token) return;
    setSaving(true);
    setError('');
    try {
      const res = await api.updateReviewerQuestionnaire(token, {
        questionnaire_answers: answers as Record<string, unknown>,
        questionnaire_step: nextSection ?? sectionId,
      });
      setProfile(res.profile);
      setPercent(res.completion_percent);
      if (nextSection) setSectionId(nextSection);
      if (!opts?.quiet) {
        toast({ variant: 'success', title: 'Saved', description: 'Profile progress saved.' });
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not save');
    } finally {
      setSaving(false);
    }
  };

  const publish = async () => {
    if (!token) return;
    setPublishing(true);
    setError('');
    try {
      await api.updateReviewerQuestionnaire(token, {
        questionnaire_answers: answers as Record<string, unknown>,
        questionnaire_step: sectionId,
      });
      const res = await api.updateReviewerProfile(token, { publish: true });
      setProfile(res.profile);
      toast({
        variant: 'success',
        title: isPublished ? 'Profile updated' : 'Published',
        description: isPublished
          ? 'Your published profile has been updated.'
          : 'Your expert profile is now visible to companies.',
      });
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not publish');
      toast({
        variant: 'error',
        title: 'Could not publish',
        description: err instanceof Error ? err.message : 'Try again.',
      });
    } finally {
      setPublishing(false);
    }
  };

  const onAvatar = async (file: File | undefined) => {
    if (!token || !file) return;
    const localPreview = URL.createObjectURL(file);
    setAvatarPreview((prev) => {
      if (prev?.startsWith('blob:')) URL.revokeObjectURL(prev);
      return localPreview;
    });
    try {
      const res = await api.uploadReviewerAvatar(token, file);
      setProfile(res.profile);
      setPercent(
        computeReviewerCompletionPercent(answers, {
          hasAvatar: true,
          hasCv: Boolean(res.profile.has_cv),
          hasExperiences: res.profile.experiences.length > 0,
        })
      );
      toast({ variant: 'success', title: 'Photo updated' });
    } catch (err) {
      setAvatarPreview(null);
      toast({ variant: 'error', title: 'Upload failed', description: err instanceof Error ? err.message : 'Try again' });
    }
  };

  const onCv = async (file: File | undefined) => {
    if (!token || !file) return;
    try {
      const res = await api.uploadReviewerCv(token, file);
      setProfile(res.profile);
      setAnswer('cv_upload', true);
      toast({ variant: 'success', title: 'CV uploaded' });
    } catch (err) {
      toast({ variant: 'error', title: 'CV upload failed', description: err instanceof Error ? err.message : 'PDF only' });
    }
  };

  const renderField = (field: ReviewerQuestionnaireField) => {
    if (field.type === 'photo') {
      return (
        <div className="space-y-2">
          <p className="m-0 text-sm font-medium text-foreground">{field.label}</p>
          <div className="flex items-center gap-4">
            {avatarPreview ? (
              <img src={avatarPreview} alt="" className="h-16 w-16 rounded-full object-cover" />
            ) : (
              <div className="flex h-16 w-16 items-center justify-center rounded-full bg-muted text-xs text-muted-foreground">
                No photo
              </div>
            )}
            <div>
              <input
                ref={avatarRef}
                type="file"
                accept="image/jpeg,image/png,image/webp,image/gif"
                className="hidden"
                onChange={(e) => onAvatar(e.target.files?.[0])}
              />
              <Button type="button" variant="secondary" size="sm" onClick={() => avatarRef.current?.click()}>
                Upload photo
              </Button>
            </div>
          </div>
        </div>
      );
    }

    if (field.type === 'cv') {
      return (
        <div className="space-y-2">
          <p className="m-0 text-sm font-medium text-foreground">{field.label}</p>
          <input ref={cvRef} type="file" accept="application/pdf,.pdf" className="hidden" onChange={(e) => onCv(e.target.files?.[0])} />
          <div className="flex flex-wrap items-center gap-2">
            <Button type="button" variant="secondary" onClick={() => cvRef.current?.click()}>
              {profile?.has_cv ? 'Replace CV (PDF)' : 'Upload CV (PDF)'}
            </Button>
            {profile?.has_cv ? <Badge variant="success">CV on file</Badge> : null}
          </div>
        </div>
      );
    }

    if (field.type === 'experiences') {
      const rows = (Array.isArray(answers.experiences) ? answers.experiences : [emptyExperience()]) as ReviewerExperience[];
      const yearOptions = Array.from({ length: 40 }, (_, i) => new Date().getFullYear() - i);
      return (
        <div className="space-y-4">
          <p className="m-0 text-sm font-medium text-foreground">{field.label}</p>
          {rows.map((row, idx) => (
            <Card key={idx} className="space-y-3 p-4">
              <Input
                label="Organization"
                value={row.organization}
                onChange={(e) => {
                  const next = [...rows];
                  next[idx] = { ...row, organization: e.target.value };
                  setAnswer('experiences', next);
                }}
              />
              <Input
                label="Title"
                value={row.title}
                onChange={(e) => {
                  const next = [...rows];
                  next[idx] = { ...row, title: e.target.value };
                  setAnswer('experiences', next);
                }}
              />
              <div className="grid gap-3 sm:grid-cols-2">
                <label className="space-y-1 text-sm">
                  <span className="font-medium">Start year</span>
                  <select
                    className="h-10 w-full rounded-button border border-border bg-white px-3 text-sm"
                    value={row.start_year || ''}
                    onChange={(e) => {
                      const next = [...rows];
                      next[idx] = { ...row, start_year: Number(e.target.value) };
                      setAnswer('experiences', next);
                    }}
                  >
                    {yearOptions.map((y) => (
                      <option key={y} value={y}>
                        {y}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="space-y-1 text-sm">
                  <span className="font-medium">End year</span>
                  <select
                    className="h-10 w-full rounded-button border border-border bg-white px-3 text-sm"
                    value={row.end_year ?? ''}
                    onChange={(e) => {
                      const next = [...rows];
                      next[idx] = { ...row, end_year: e.target.value ? Number(e.target.value) : null };
                      setAnswer('experiences', next);
                    }}
                  >
                    <option value="">Current</option>
                    {yearOptions.map((y) => (
                      <option key={y} value={y}>
                        {y}
                      </option>
                    ))}
                  </select>
                </label>
              </div>
              {rows.length > 1 ? (
                <Button
                  type="button"
                  size="sm"
                  variant="secondary"
                  onClick={() => setAnswer(
                    'experiences',
                    rows.filter((_, i) => i !== idx)
                  )}
                >
                  Remove role
                </Button>
              ) : null}
            </Card>
          ))}
          <Button type="button" variant="secondary" onClick={() => setAnswer('experiences', [...rows, emptyExperience()])}>
            + Add role
          </Button>
        </div>
      );
    }

    if (field.type === 'text' || field.type === 'textarea') {
      const value = typeof answers[field.id] === 'string' ? (answers[field.id] as string) : '';
      if (field.type === 'textarea') {
        return (
          <Textarea
            label={field.label}
            rows={4}
            value={value}
            readOnly={field.readOnly}
            placeholder={field.placeholder}
            onChange={(e) => setAnswer(field.id, e.target.value)}
          />
        );
      }
      return (
        <Input
          label={field.label}
          value={value}
          readOnly={field.readOnly}
          placeholder={field.placeholder}
          onChange={(e) => setAnswer(field.id, e.target.value)}
        />
      );
    }

    if (field.type === 'searchable_select') {
      return (
        <SearchableSelectField
          field={field}
          value={typeof answers[field.id] === 'string' ? (answers[field.id] as string) : ''}
          onChange={(v) => setAnswer(field.id, v)}
          isNarrow={isNarrow}
        />
      );
    }

    if (field.type === 'single_select') {
      const value = typeof answers[field.id] === 'string' ? (answers[field.id] as string) : '';
      return (
        <fieldset className="space-y-2">
          <legend className="text-sm font-medium text-foreground">{field.label}</legend>
          <div className="grid gap-2 sm:grid-cols-2">
            {(field.options || []).map((opt) => (
              <ChoiceButton key={opt} active={value === opt} onClick={() => setAnswer(field.id, opt)}>
                {opt}
              </ChoiceButton>
            ))}
          </div>
        </fieldset>
      );
    }

    const selected = Array.isArray(answers[field.id]) ? (answers[field.id] as string[]) : [];
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
    return (
      <fieldset className="space-y-2">
        <legend className="text-sm font-medium text-foreground">{field.label}</legend>
        <div className="grid gap-2 sm:grid-cols-2">
          {(field.options || []).map((opt) => (
            <ChoiceButton key={opt} active={selected.includes(opt)} onClick={() => toggle(opt)}>
              {opt}
            </ChoiceButton>
          ))}
        </div>
      </fieldset>
    );
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
    <nav className={cn(isNarrow ? 'flex gap-2 overflow-x-auto pb-1' : 'space-y-1')} aria-label="Profile sections">
      {REVIEWER_QUESTIONNAIRE_SECTIONS.map((s) => {
        const touched = reviewerSectionTouched(s.id, answers, extras);
        const active = s.id === sectionId;
        return (
          <button
            key={s.id}
            type="button"
            onClick={() => persist(s.id, { quiet: true })}
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
          title="Expert profile"
          description="This profile helps companies trust your expertise and helps us match you to the right reviews. Nothing is required to navigate — fill what you can."
          actions={
            <Button type="button" variant="secondary" onClick={() => setPreviewOpen(true)}>
              <Eye className="mr-1.5 h-4 w-4" />
              Preview as company
            </Button>
          }
        />
        <div className="flex flex-wrap items-center gap-3">
          <div className="min-w-0 flex-1">
            <ProgressBar value={percent} />
          </div>
          <span className="shrink-0 text-sm font-semibold tabular-nums text-foreground">{percent}%</span>
          {isPublished ? <Badge variant="success">Published</Badge> : <Badge variant="warning">Draft</Badge>}
          {profile?.verification_signals ? (
            <Badge variant="info">
              <ShieldCheck className="mr-1 inline h-3 w-3" />
              Verification signals
            </Badge>
          ) : null}
        </div>
        {isNarrow ? sectionNav : null}
      </div>

      {error ? <p className="text-sm text-status-error">{error}</p> : null}

      <Modal
        open={previewOpen}
        onClose={() => setPreviewOpen(false)}
        title="How companies see you"
        className="sm:max-w-xl"
      >
        <div className="space-y-3">
          <p className="m-0 text-sm text-muted-foreground">
            This is the profile card clients see when you are assigned
            {isPublished ? '.' : ' — publish when you are ready for it to appear.'}
          </p>
          <ExpertReviewerCard reviewer={companyPreview} token={token} />
        </div>
      </Modal>

      <div className="grid gap-4 lg:grid-cols-[220px_1fr]">
        {!isNarrow ? (
          <aside className="lg:sticky lg:top-36 lg:self-start">
            <Card className="p-2">{sectionNav}</Card>
          </aside>
        ) : null}

        <Card className="space-y-6 p-4 sm:p-6">
          <div>
            <p className="m-0 text-xs font-medium uppercase tracking-wide text-muted-foreground">
              Section {section.id} of {REVIEWER_QUESTIONNAIRE_SECTIONS.length}
            </p>
            <h2 className="m-0 mt-1 text-xl font-medium text-foreground">{section.title}</h2>
          </div>

          <div className="space-y-6">{section.fields.map((field) => <div key={field.id}>{renderField(field)}</div>)}</div>

          <div className="hidden flex-wrap gap-2 border-t border-border pt-4 lg:flex">
            <Button
              variant="secondary"
              disabled={sectionId <= 1 || saving}
              onClick={() => persist(sectionId - 1, { quiet: true })}
            >
              <ChevronLeft className="mr-1 h-4 w-4" />
              Back
            </Button>
            {sectionId < 9 ? (
              <Button loading={saving} onClick={() => persist(sectionId + 1)}>
                Save & continue
                <ChevronRight className="ml-1 h-4 w-4" />
              </Button>
            ) : (
              <Button loading={saving} onClick={() => persist(9)}>
                Save profile
              </Button>
            )}
            <Button variant="secondary" loading={publishing} onClick={publish}>
              {isPublished ? 'Update published profile' : 'Publish profile'}
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
            onClick={() => persist(sectionId - 1, { quiet: true })}
          >
            Back
          </Button>
          {sectionId < 9 ? (
            <Button size="sm" className="flex-[2]" loading={saving} onClick={() => persist(sectionId + 1)}>
              Save & continue
            </Button>
          ) : (
            <Button size="sm" className="flex-[2]" loading={saving} onClick={() => persist(9)}>
              Save
            </Button>
          )}
          <Button size="sm" variant="secondary" loading={publishing} onClick={publish}>
            {isPublished ? 'Update' : 'Publish'}
          </Button>
        </div>
      </div>
    </div>
  );
}
