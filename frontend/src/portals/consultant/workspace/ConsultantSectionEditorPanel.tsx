import { useCallback, useEffect, useState } from 'react';
import {
  api,
  type ReportSectionOverride,
  type ReportSectionTemplate,
  type SectionOverrideAction,
} from '@/lib/api';
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
  tools_catalog: 'Capabilities',
  methodology: 'Methodology',
  expert_verdict: 'Expert assessment',
};

const label = (key: string | null) => (key ? SECTION_LABELS[key] ?? key : '');

type Props = {
  token: string;
  companyId: number;
  reportId: number;
  disabled?: boolean;
  onPreview?: () => void;
};

/**
 * Consultant editorial control over the report body: hide a built-in section,
 * add an editorial note to one, or add a whole new custom section. Changes are
 * applied to the deliverable when the report is regenerated on approval.
 */
export function ConsultantSectionEditorPanel({ token, companyId, reportId, disabled, onPreview }: Props) {
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
  // The section library. Adding a section always worked; what it lacked was any
  // structure -- a consultant got an empty textarea and no indication that a real
  // deliverable wants assumptions, risks, quick wins, benchmarks.
  const [templates, setTemplates] = useState<ReportSectionTemplate[]>([]);
  const [templateKey, setTemplateKey] = useState<string | null>(null);
  const [showAllTemplates, setShowAllTemplates] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setLoadError(false);
    try {
      const data = await api.consultantSectionOverrides(token, companyId, reportId);
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

  useEffect(() => {
    api
      .consultantSectionTemplates(token)
      .then((d) => setTemplates(d.templates))
      .catch(() => setTemplates([]));
  }, [token]);

  const reset = () => {
    setTitle('');
    setBody('');
    setTemplateKey(null);
  };

  // Prefill from the library. The scaffold is a skeleton that poses the questions
  // the section must answer -- the consultant replaces it with judgement rather
  // than staring at a cursor. section_key carries the template key so the
  // rendered page can show what the section is for.
  const applyTemplate = (template: ReportSectionTemplate) => {
    setAction('add');
    setTemplateKey(template.key);
    setTitle(template.title);
    setBody(template.scaffold);
    setAnchor(template.anchor);
  };

  const submit = async () => {
    if (action === 'add' && (!title.trim() || !body.trim())) return;
    if (action === 'edit' && !body.trim()) return;
    setSaving(true);
    try {
      await api.createConsultantSectionOverride(token, companyId, reportId, {
        action,
        section_key: action === 'add' ? templateKey : sectionKey,
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
      await api.createConsultantSectionOverride(token, companyId, reportId, { action: 'hide', section_key: key });
      await load();
    } finally {
      setSaving(false);
    }
  };

  const remove = async (id: number) => {
    await api.deleteConsultantSectionOverride(token, companyId, reportId, id);
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
          <div className="flex items-start justify-between gap-3">
            <p className="text-xs text-text-secondary">
              Hide sections, add an editorial note, or add your own section. Changes are baked in when the report is
              approved.
            </p>
            {onPreview && (
              <Button variant="secondary" size="sm" className="shrink-0" onClick={onPreview}>
                Preview with edits
              </Button>
            )}
          </div>
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
                    {o.consultant_name && <p className="mt-0.5 text-[11px] text-text-secondary">by {o.consultant_name}</p>}
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

          {/* The section library */}
          {!disabled && templates.length > 0 && (
            <div className="space-y-2 border-t border-border pt-4">
              <p className="text-xs font-semibold uppercase tracking-wide text-text-secondary">
                Sections a deliverable should carry
              </p>
              <p className="text-xs text-text-secondary">
                These need your judgement — the generated report cannot produce them from evidence alone.
              </p>
              <div className="grid gap-2 sm:grid-cols-2">
                {(showAllTemplates ? templates : templates.filter((t) => t.recommended)).map((t) => {
                  const used = overrides.some((o) => o.action === 'add' && o.section_key === t.key);
                  return (
                    <button
                      key={t.key}
                      type="button"
                      disabled={used}
                      onClick={() => applyTemplate(t)}
                      className={`rounded-md border px-3 py-2 text-left transition ${
                        templateKey === t.key
                          ? 'border-accent bg-accent/5'
                          : 'border-border hover:border-accent/60'
                      } disabled:cursor-not-allowed disabled:opacity-50`}
                    >
                      <div className="flex items-center gap-2">
                        <span className="text-sm font-medium text-text-primary">{t.title}</span>
                        {used && <Badge variant="success">Added</Badge>}
                        {!used && t.recommended && <Badge variant="neutral">Recommended</Badge>}
                      </div>
                      <p className="mt-0.5 text-xs leading-snug text-text-secondary">{t.purpose}</p>
                    </button>
                  );
                })}
              </div>
              <button
                type="button"
                className="text-xs text-accent hover:underline"
                onClick={() => setShowAllTemplates((v) => !v)}
              >
                {showAllTemplates
                  ? 'Show recommended only'
                  : `Show all ${templates.length} sections`}
              </button>
            </div>
          )}

          {/* Add / rewrite a section */}
          {!disabled && (
            <div className="space-y-3 border-t border-border pt-4">
              <Select
                label="What do you want to do?"
                value={action}
                onChange={(e) => setAction(e.target.value as SectionOverrideAction)}
                options={[
                  { value: 'add', label: 'Add a new section' },
                  { value: 'edit', label: 'Rewrite a generated section' },
                ]}
              />
              {action === 'edit' && (
                <>
                  <Select
                    label="Section to rewrite"
                    value={sectionKey}
                    onChange={(e) => setSectionKey(e.target.value)}
                    options={sections.map((k) => ({ value: k, label: label(k) }))}
                  />
                  {/* This used to be labelled "add an editorial note", which
                      misdescribed what happens: the text REPLACES the generated
                      section in the deliverable rather than sitting beside it. */}
                  <p className="text-xs text-warning">
                    Your text replaces the generated {label(sectionKey) || 'section'} entirely — it does not appear
                    alongside it.
                  </p>
                </>
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
                  label={action === 'add' ? 'Section title' : 'Replacement heading (optional)'}
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  rows={1}
                />
              )}
              <Textarea
                label={action === 'add' ? 'Section content' : 'Your replacement text'}
                value={body}
                onChange={(e) => setBody(e.target.value)}
                rows={action === 'add' && templateKey ? 14 : 5}
              />
              {/* The deliverable renders this light markup as real typography —
                  worth saying, since the alternative is a wall of plain text. */}
              <p className="-mt-1 text-xs text-text-secondary">
                <code>##</code> for a heading, <code>-</code> for a bullet, <code>**bold**</code>,{' '}
                <code>*italic*</code>.
              </p>
              <div className="flex justify-end">
                <Button onClick={submit} loading={saving} disabled={saving}>
                  {action === 'add' ? 'Add section' : 'Replace section'}
                </Button>
              </div>
            </div>
          )}
        </div>
      )}
    </Card>
  );
}
