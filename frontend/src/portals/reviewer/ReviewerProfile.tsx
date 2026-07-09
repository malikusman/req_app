import { useEffect, useRef, useState, type FormEvent } from 'react';
import { Link } from 'react-router-dom';
import {
  api,
  type ReviewerExperience,
  type ReviewerProfile,
  type ReviewerProfilePayload,
} from '../../lib/api';
import { useReviewerToken } from '../../lib/auth';
import { PageHeader, Card, Button, Input, Badge, Textarea } from '../../components/ui';
import { ExpertReviewerCard } from '../../components/ExpertReviewerCard';

const emptyExperience = (): ReviewerExperience => ({
  organization: '',
  title: '',
  start_year: new Date().getFullYear() - 5,
  end_year: null,
  summary: '',
});

export function ReviewerProfile() {
  const token = useReviewerToken();
  const fileRef = useRef<HTMLInputElement>(null);
  const [profile, setProfile] = useState<ReviewerProfile | null>(null);
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [form, setForm] = useState<ReviewerProfilePayload>({});
  const [experiences, setExperiences] = useState<ReviewerExperience[]>([emptyExperience()]);
  const [tagInput, setTagInput] = useState('');
  const [error, setError] = useState('');
  const [saving, setSaving] = useState(false);
  const [loading, setLoading] = useState(true);

  const load = () => {
    if (!token) return;
    api.reviewerProfile(token).then((d) => {
      setProfile(d.profile);
      setName(d.user.name);
      setEmail(d.user.email);
      setForm({
        headline: d.profile.headline || '',
        bio: d.profile.bio || '',
        linkedin_url: d.profile.linkedin_url || '',
        website_url: d.profile.website_url || '',
        location: d.profile.location || '',
        timezone: d.profile.timezone || '',
        years_experience: d.profile.years_experience,
        languages: d.profile.languages,
        expertise_tags: d.profile.expertise_tags,
        industries: d.profile.industries,
      });
      setExperiences(
        d.profile.experiences.length > 0 ? d.profile.experiences : [emptyExperience()]
      );
    }).finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
  }, [token]);

  const addTag = (tag: string) => {
    const t = tag.trim();
    if (!t) return;
    const tags = form.expertise_tags || [];
    if (tags.length >= 12 || tags.includes(t)) return;
    setForm({ ...form, expertise_tags: [...tags, t] });
    setTagInput('');
  };

  const removeTag = (tag: string) => {
    setForm({ ...form, expertise_tags: (form.expertise_tags || []).filter((x) => x !== tag) });
  };

  const save = async (publish?: boolean) => {
    if (!token) return;
    setSaving(true);
    setError('');
    try {
      const res = await api.updateReviewerProfile(token, {
        name,
        email,
        ...form,
        headline: form.headline || undefined,
        bio: form.bio || undefined,
        experiences: experiences.filter((e) => e.organization && e.title),
        publish,
      });
      setProfile(res.profile);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Save failed');
    } finally {
      setSaving(false);
    }
  };

  const onSubmit = (e: FormEvent) => {
    e.preventDefault();
    save();
  };

  const onAvatar = async (file: File) => {
    if (!token) return;
    setError('');
    try {
      const res = await api.uploadReviewerAvatar(token, file);
      setProfile(res.profile);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Upload failed');
    }
  };

  if (loading) return <p className="text-sm text-muted-foreground">Loading profile…</p>;

  const previewCard = profile
    ? {
        id: 0,
        name: name || 'You',
        headline: form.headline || null,
        avatar_url: profile.avatar_url,
        expertise_tags: form.expertise_tags || [],
        industries: form.industries || [],
        years_experience: form.years_experience ?? null,
        languages: form.languages || [],
        location: form.location || null,
        linkedin_url: form.linkedin_url || null,
        profile_status: profile.profile_status,
        platform_verified: !!profile.platform_verified_at,
      }
    : null;

  return (
    <div className="space-y-6">
      <PageHeader
        title="Your profile"
        description="Build a credible expert profile before reviewing client reports."
        breadcrumbs={[{ label: 'Dashboard', href: '/reviewer/dashboard' }, { label: 'Profile' }]}
      />

      {profile && profile.profile_status === 'draft' && !profile.completeness.complete && (
        <div className="rounded-lg border border-status-warning/40 bg-status-warningBg px-4 py-3 text-sm text-foreground">
          Profile {profile.completeness.percent}% complete — missing:{' '}
          {profile.completeness.missing.join(', ')}. Publish when ready for companies to see you.
        </div>
      )}

      {error && <p className="text-sm text-destructive">{error}</p>}

      <div className="grid gap-6 lg:grid-cols-2">
        <form onSubmit={onSubmit} className="space-y-6">
          <Card title="Photo">
            <div className="flex items-center gap-4">
              {profile?.avatar_url ? (
                <img src={profile.avatar_url} alt="" className="h-20 w-20 rounded-full object-cover" />
              ) : (
                <div className="flex h-20 w-20 items-center justify-center rounded-full bg-muted text-2xl text-muted-foreground">
                  ?
                </div>
              )}
              <input
                ref={fileRef}
                type="file"
                accept="image/jpeg,image/png,image/webp,image/gif"
                className="hidden"
                onChange={(e) => {
                  const f = e.target.files?.[0];
                  if (f) onAvatar(f);
                }}
              />
              <Button type="button" variant="secondary" onClick={() => fileRef.current?.click()}>
                Upload photo
              </Button>
            </div>
          </Card>

          <Card title="Account">
            <div className="space-y-4">
              <Input label="Name" value={name} onChange={(e) => setName(e.target.value)} required />
              <Input label="Email" type="email" value={email} onChange={(e) => setEmail(e.target.value)} required />
            </div>
          </Card>

          <Card title="Professional identity">
            <div className="space-y-4">
              <Input
                label="Headline"
                value={form.headline || ''}
                onChange={(e) => setForm({ ...form, headline: e.target.value })}
                placeholder="Operations transformation · 15 yrs · GCC"
              />
              <Textarea
                label="Bio (min 80 characters)"
                value={form.bio || ''}
                onChange={(e) => setForm({ ...form, bio: e.target.value })}
                rows={5}
              />
              <Input
                label="LinkedIn URL"
                value={form.linkedin_url || ''}
                onChange={(e) => setForm({ ...form, linkedin_url: e.target.value })}
                placeholder="https://linkedin.com/in/…"
              />
              <Input
                label="Website"
                value={form.website_url || ''}
                onChange={(e) => setForm({ ...form, website_url: e.target.value })}
              />
              <Input
                label="Location"
                value={form.location || ''}
                onChange={(e) => setForm({ ...form, location: e.target.value })}
              />
              <Input
                label="Years of experience"
                type="number"
                value={form.years_experience ?? ''}
                onChange={(e) =>
                  setForm({
                    ...form,
                    years_experience: e.target.value ? Number(e.target.value) : null,
                  })
                }
              />
            </div>
          </Card>

          <Card title="Strengths">
            <div className="mb-2 flex flex-wrap gap-1">
              {(form.expertise_tags || []).map((tag) => (
                <button
                  key={tag}
                  type="button"
                  className="inline-flex items-center gap-1 rounded-full border border-border px-2 py-0.5 text-xs"
                  onClick={() => removeTag(tag)}
                >
                  {tag} ×
                </button>
              ))}
            </div>
            <div className="flex gap-2">
              <Input
                label="Add tag"
                value={tagInput}
                onChange={(e) => setTagInput(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter') {
                    e.preventDefault();
                    addTag(tagInput);
                  }
                }}
              />
              <Button type="button" className="self-end" variant="secondary" onClick={() => addTag(tagInput)}>
                Add
              </Button>
            </div>
            <div className="mt-3 flex flex-wrap gap-1">
              {(profile?.suggested_expertise_tags || []).map((tag) => (
                <button
                  key={tag}
                  type="button"
                  onClick={() => addTag(tag)}
                  className="rounded-full bg-muted px-2 py-0.5 text-xs text-muted-foreground hover:bg-border"
                >
                  + {tag}
                </button>
              ))}
            </div>
          </Card>

          <Card title="Experience">
            {experiences.map((exp, i) => (
              <div key={i} className="mb-4 space-y-3 border-b border-border pb-4 last:border-0">
                <Input
                  label="Organization"
                  value={exp.organization}
                  onChange={(e) => {
                    const next = [...experiences];
                    next[i] = { ...exp, organization: e.target.value };
                    setExperiences(next);
                  }}
                />
                <Input
                  label="Title"
                  value={exp.title}
                  onChange={(e) => {
                    const next = [...experiences];
                    next[i] = { ...exp, title: e.target.value };
                    setExperiences(next);
                  }}
                />
                <div className="grid grid-cols-2 gap-3">
                  <Input
                    label="Start year"
                    type="number"
                    value={exp.start_year}
                    onChange={(e) => {
                      const next = [...experiences];
                      next[i] = { ...exp, start_year: Number(e.target.value) };
                      setExperiences(next);
                    }}
                  />
                  <Input
                    label="End year (blank = current)"
                    type="number"
                    value={exp.end_year ?? ''}
                    onChange={(e) => {
                      const next = [...experiences];
                      next[i] = {
                        ...exp,
                        end_year: e.target.value ? Number(e.target.value) : null,
                      };
                      setExperiences(next);
                    }}
                  />
                </div>
              </div>
            ))}
            <Button
              type="button"
              variant="secondary"
              size="sm"
              onClick={() => setExperiences([...experiences, emptyExperience()])}
            >
              Add role
            </Button>
          </Card>

          <div className="flex flex-wrap gap-3">
            <Button type="submit" loading={saving}>
              Save draft
            </Button>
            <Button
              type="button"
              variant="secondary"
              loading={saving}
              onClick={() => save(true)}
              disabled={!profile?.completeness.complete}
            >
              Publish profile
            </Button>
            <Link to="/reviewer/dashboard" className="self-center text-sm text-accent hover:underline">
              Back to dashboard
            </Link>
          </div>
        </form>

        <div className="space-y-4">
          <h3 className="m-0 text-sm font-medium text-muted-foreground">Preview — how you appear to clients</h3>
          {previewCard && <ExpertReviewerCard reviewer={previewCard} />}
          {profile && (
            <p className="text-xs text-muted-foreground">
              Status:{' '}
              <Badge variant={profile.profile_status === 'published' ? 'success' : 'neutral'}>
                {profile.profile_status}
              </Badge>
            </p>
          )}
        </div>
      </div>
    </div>
  );
}
