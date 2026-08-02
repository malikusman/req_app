import { useCallback, useEffect, useState } from 'react';
import { api, type ReportSectionOverride, type SectionOverrideAction } from '@/lib/api';
import { Card } from '@/components/ui/Card';
import { Button } from '@/components/ui/Button';
import { Select } from '@/components/ui/Select';
import { Textarea } from '@/components/ui/Textarea';
import { Badge } from '@/components/ui/Badge';
import { useToast } from '@/components/ui/ToastProvider';

const SECTION_LABELS: Record<string, string> = {
  executive_summary: 'Executive summary',
  readiness: 'Readiness',
  company_context: 'Company context',
  participation: 'Participation',
  delta: 'What changed',
  signals: 'Signals',
  patterns: 'Patterns',
  implications: 'Implications',
  recommendations: 'Recommendations',
  roadmap: 'Roadmap',
  opportunities: 'Opportunities',
  tools_catalog: 'Capabilities & evidence',
  supporting_media: 'Supporting media',
  methodology: 'Methodology',
};

const label = (key: string | null) => (key ? SECTION_LABELS[key] ?? key : '');

type Props = {
  token: string;
  companyId: number;
  reportId: number;
  disabled?: boolean;
};

/**
 * Reviewer editorial control over the report body: hide a built-in section,
 * add an editorial note to one, or add a whole new custom section. Changes are
 * applied to the deliverable when the report is regenerated on approval.
 */
export function ReviewerSectionEditorPanel({ token, companyId, reportId, disabled }: Props) {
  const { toast } = useToast();
  const [sections, setSections] = useState<string[]>([]);
  const [overrides, setOverrides] = useState<ReportSectionOverride[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(false);

  // Add / edit form state
  const [action, setAction] = useState<SectionOverrideAction>('add');
  const [sectionKey, setSectionKey] = useState('');
  const [anchor, setAnchor] = useState('recommendations');
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [saving, setSaving] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setLoadError(false);
    try {
      const data = await api.reviewerSectionOverrides(token, companyId, reportId);
      setSections(data.built_in_sections);
      setOverrides(data.overrides);
      if (!sectionKey && data.built_in_sections.length) setSectionKey(data.built_in_sections[0]);
    } catch {
      setLoadError(true);
    } finally {
      setLoading(false);
    }
  }, [token, companyId, reportId, sectionKey]);

  useEffect(() => {
    load();
  }, [load]);

  const reset = () => {
    setTitle('');
    setBody('');
  };

  const submit = async () => {
    if (action === 'add' && (!title.trim() || !body.trim())) return;
    if (action === 'edit' && !body.trim()) return;
    setSaving(true);
    try {
      await api.createReviewerSectionOverride(token, companyId, reportId, {
        action,
        section_key: action === 'add' ? null : sectionKey,
        anchor_section: action === 'add' ? anchor : null,
        title: title.trim() || null,
        body: body.trim() || null,
      });
      toast({ variant: 'success', title: 'Saved', description: 'Applies when the report is regenerated.' });
      reset();
      await load();
    } catch (e) {
      toast({ variant: 'error', title: 'Could not save', description: e instanceof Error ? e.message : 'Try again.' });
    } finally {
      setSaving(false);
    }
  };

  const hideSection = async (key: string) => {
    setSaving(true);
    try {
      await api.createReviewerSectionOverride(token, companyId, reportId, { action: 'hide', section_key: key });
      await load();
    } finally {
      setSaving(false);
    }
  };

  const remove = async (id: number) => {
    await api.deleteReviewerSectionOverride(token, companyId, reportId, id);
    await load();
  };

  const hiddenKeys = new Set(overrides.filter((o) => o.action === 'hide').map((o) => o.section_key));

  return (
    <Card title="Edit the deliverable">
      {loadError ? (
        <div className="rounded-button border border-status-error/30 bg-status-errorBg px-3 py-2 text-sm text-status-error">
          Couldn't load section edits.{' '}
          <Button variant="secondary" size="sm" onClick={load}>
            Retry
          </Button>
        </div>
      ) : loading ? (
        <p className="text-sm text-text-secondary">Loading…</p>
      ) : (
        <div className="space-y-5">
          <p className="text-xs text-text-secondary">
            Hide sections, add an editorial note, or add your own section. Open the report preview
            (&ldquo;With your edits&rdquo;) to see the result live; changes are baked in when the report is approved.
          </p>
          {/* Existing overrides */}
          {overrides.length > 0 && (
            <ul className="space-y-2">
              {overrides.map((o) => (
                <li
                  key={o.id}
                  className="flex items-start justify-between gap-3 rounded-md border border-border bg-surface-muted px-3 py-2"
                >
                  <div className="min-w-0">
                    <div className="flex items-center gap-2">
                      <Badge variant={o.action === 'hide' ? 'warning' : 'neutral'}>{o.action}</Badge>
                      <span className="truncate text-sm font-medium text-text-primary">
                        {o.action === 'add' ? o.title : label(o.section_key)}
                      </span>
                    </div>
                    {o.body && <p className="mt-1 line-clamp-2 text-xs text-text-secondary">{o.body}</p>}
                    {o.reviewer_name && <p className="mt-0.5 text-[11px] text-text-secondary">by {o.reviewer_name}</p>}
                  </div>
                  {o.editable && !disabled && (
                    <Button variant="ghost" size="sm" onClick={() => remove(o.id)}>
                      Remove
                    </Button>
                  )}
                </li>
              ))}
            </ul>
          )}

          {/* Quick hide toggles */}
          {!disabled && (
            <div>
              <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-text-secondary">Hide a section</p>
              <div className="flex flex-wrap gap-2">
                {sections
                  .filter((k) => !hiddenKeys.has(k))
                  .map((k) => (
                    <button
                      key={k}
                      type="button"
                      onClick={() => hideSection(k)}
                      disabled={saving}
                      className="rounded-full border border-border px-3 py-1 text-xs text-text-secondary transition hover:border-status-error hover:text-status-error disabled:opacity-50"
                    >
                      Hide {label(k)}
                    </button>
                  ))}
              </div>
            </div>
          )}

          {/* Add note / custom section */}
          {!disabled && (
            <div className="space-y-3 border-t border-border pt-4">
              <Select
                label="What do you want to do?"
                value={action}
                onChange={(e) => setAction(e.target.value as SectionOverrideAction)}
                options={[
                  { value: 'add', label: 'Add a new section' },
                  { value: 'edit', label: 'Add an editorial note to a section' },
                ]}
              />
              {action === 'edit' && (
                <Select
                  label="Section"
                  value={sectionKey}
                  onChange={(e) => setSectionKey(e.target.value)}
                  options={sections.map((k) => ({ value: k, label: label(k) }))}
                />
              )}
              {action === 'add' && (
                <Select
                  label="Place after"
                  value={anchor}
                  onChange={(e) => setAnchor(e.target.value)}
                  options={sections.map((k) => ({ value: k, label: label(k) }))}
                />
              )}
              {(action === 'add' || action === 'edit') && (
                <Textarea
                  label={action === 'add' ? 'Section title' : 'Note heading (optional)'}
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  rows={1}
                />
              )}
              <Textarea
                label={action === 'add' ? 'Section content' : 'Your note'}
                value={body}
                onChange={(e) => setBody(e.target.value)}
                rows={5}
              />
              <div className="flex justify-end">
                <Button onClick={submit} loading={saving} disabled={saving}>
                  {action === 'add' ? 'Add section' : 'Add note'}
                </Button>
              </div>
            </div>
          )}
        </div>
      )}
    </Card>
  );
}
