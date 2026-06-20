import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react';
import { Link, useParams } from 'react-router-dom';
import { api, type MediaAttachment, type ReportReviewPayload, type ReviewerReportDetail } from '../../lib/api';
import { useReviewerToken } from '../../lib/auth';
import { ConversationMediaList } from '../../components/ConversationMediaCard';
import {
  PageHeader,
  Card,
  Button,
  Select,
  Textarea,
  Input,
  Badge,
  Skeleton,
  StrengthBar,
} from '../../components/ui';
import { cn } from '../../lib/cn';

const SECTIONS = [
  'executive_summary',
  'readiness',
  'participation',
  'delta',
  'signals',
  'patterns',
  'recommendations',
] as const;

type SectionKey = (typeof SECTIONS)[number];

function SectionContent({ section, snapshot }: { section: SectionKey; snapshot: Record<string, unknown> }) {
  if (section === 'executive_summary') {
    const company = snapshot.company as { name?: string } | undefined;
    return (
      <p className="text-sm text-text-secondary">
        Discovery report for <strong>{company?.name ?? 'this company'}</strong>. Review each section and add comments
        for the platform team.
      </p>
    );
  }
  if (section === 'readiness') {
    const r = snapshot.readiness as { score?: number; breakdown?: Record<string, number> } | undefined;
    return (
      <div className="space-y-3">
        <p className="text-2xl font-semibold text-text-primary">{r?.score ?? 0}%</p>
        {r?.breakdown &&
          Object.entries(r.breakdown).map(([k, v]) => (
            <div key={k}>
              <div className="mb-1 flex justify-between text-sm">
                <span className="capitalize">{k.replace(/_/g, ' ')}</span>
                <span>{v}%</span>
              </div>
              <StrengthBar strength={v / 100} />
            </div>
          ))}
      </div>
    );
  }
  if (section === 'participation') {
    const p = snapshot.participation as Record<string, number> | undefined;
    if (!p) return <p className="text-sm text-text-secondary">No participation data.</p>;
    return (
      <ul className="space-y-2 text-sm">
        {Object.entries(p).map(([k, v]) => (
          <li key={k} className="flex justify-between">
            <span className="capitalize text-text-secondary">{k.replace(/_/g, ' ')}</span>
            <strong>{typeof v === 'number' && v < 1 ? `${Math.round(v * 100)}%` : v}</strong>
          </li>
        ))}
      </ul>
    );
  }
  if (section === 'delta') {
    const d = snapshot.delta_from_previous as Record<string, unknown> | undefined;
    if (!d) return <p className="text-sm text-text-secondary">First report — no delta.</p>;
    return <pre className="overflow-auto rounded-button bg-surface-muted p-3 text-xs">{JSON.stringify(d, null, 2)}</pre>;
  }
  if (section === 'signals') {
    const signals =
      (snapshot.signals as {
        label: string;
        strength: number;
        departments: string[];
        evidence_count?: number;
        multimodal_evidence?: { attachment_type: string; excerpt?: string }[];
      }[]) || [];
    return (
      <ul className="space-y-3">
        {signals.map((s, i) => (
          <li key={i} className="rounded-button border border-border p-3">
            <div className="flex justify-between text-sm font-medium">
              <span>{s.label}</span>
              <span>{Math.round(s.strength * 100)}%</span>
            </div>
            <StrengthBar strength={s.strength} className="mt-2" />
            <p className="mt-1 text-xs text-text-secondary">{s.departments?.join(', ')}</p>
            {s.evidence_count != null && (
              <p className="mt-1 text-xs text-text-secondary">{s.evidence_count} evidence mentions</p>
            )}
            {s.multimodal_evidence && s.multimodal_evidence.length > 0 && (
              <ul className="mt-2 space-y-1 text-xs text-text-secondary">
                {s.multimodal_evidence.map((item, idx) => (
                  <li key={idx}>
                    {item.attachment_type}: {item.excerpt || 'Supporting media'}
                  </li>
                ))}
              </ul>
            )}
          </li>
        ))}
      </ul>
    );
  }
  if (section === 'patterns') {
    const patterns = (snapshot.patterns as { title: string; description?: string; confidence: number }[]) || [];
    return (
      <ul className="space-y-3">
        {patterns.map((p, i) => (
          <li key={i} className="rounded-button border border-border p-3">
            <div className="flex justify-between">
              <strong className="text-sm">{p.title}</strong>
              <Badge variant="info">{Math.round(p.confidence * 100)}%</Badge>
            </div>
            {p.description && <p className="mt-1 text-sm text-text-secondary">{p.description}</p>}
          </li>
        ))}
      </ul>
    );
  }
  if (section === 'recommendations') {
    const recs = (snapshot.recommendations as { title: string; description?: string; priority?: string }[]) || [];
    return (
      <ul className="space-y-3">
        {recs.map((r, i) => (
          <li key={i} className="rounded-button border border-border p-3">
            <strong className="text-sm">{r.title}</strong>
            {r.priority && (
              <Badge variant="neutral" className="ml-2">
                {r.priority}
              </Badge>
            )}
            {r.description && <p className="mt-1 text-sm text-text-secondary">{r.description}</p>}
          </li>
        ))}
      </ul>
    );
  }
  return null;
}

export function ReviewerReportReview() {
  const { companyId, reportId } = useParams();
  const token = useReviewerToken();
  const [payload, setPayload] = useState<ReportReviewPayload | null>(null);
  const [report, setReport] = useState<ReviewerReportDetail | null>(null);
  const [activeSection, setActiveSection] = useState<SectionKey>('executive_summary');
  const [note, setNote] = useState('');
  const [commentBody, setCommentBody] = useState('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [companyMedia, setCompanyMedia] = useState<MediaAttachment[]>([]);

  const load = useCallback(() => {
    if (!token || !companyId || !reportId) return;
    Promise.all([
      api.reviewerReportReview(token, Number(companyId), Number(reportId)),
      api.reviewerReport(token, Number(companyId), Number(reportId)),
      api.reviewerMediaAttachments(token, Number(companyId)).catch(() => ({ media_attachments: [] as MediaAttachment[] })),
    ])
      .then(([reviewData, reportData, mediaData]) => {
        setPayload(reviewData);
        setReport(reportData.report);
        setNote(reviewData.review.overall_note || '');
        setCompanyMedia(mediaData.media_attachments);
      })
      .catch((e) => setError(e instanceof Error ? e.message : 'Failed to load'))
      .finally(() => setLoading(false));
  }, [token, companyId, reportId]);

  useEffect(() => {
    load();
    const t = setInterval(load, 15000);
    return () => clearInterval(t);
  }, [load]);

  const setSectionStatus = async (sectionKey: string, status: string) => {
    if (!token || !companyId || !reportId) return;
    await api.updateSectionState(token, Number(companyId), Number(reportId), sectionKey, status);
    load();
  };

  const addComment = async (e: FormEvent) => {
    e.preventDefault();
    if (!token || !companyId || !reportId || !commentBody.trim()) return;
    await api.addReviewComment(token, Number(companyId), Number(reportId), {
      section_key: activeSection,
      body: commentBody.trim(),
    });
    setCommentBody('');
    load();
  };

  const saveNote = async () => {
    if (!token || !companyId || !reportId) return;
    await api.updateReviewerReportReview(token, Number(companyId), Number(reportId), { overall_note: note });
    load();
  };

  const submitReview = async () => {
    if (!token || !companyId || !reportId) return;
    if (!window.confirm('Submit your review? You can still view co-reviewer notes.')) return;
    await api.submitReviewerReportReview(token, Number(companyId), Number(reportId));
    load();
  };

  if (loading) {
    return (
      <div className="space-y-6">
        <Skeleton variant="text" />
        <Skeleton variant="card" />
      </div>
    );
  }

  if (!payload || !report) {
    return <p className="text-status-error">{error || 'Review not found'}</p>;
  }

  const review = payload.review;
  const submitted = review.status === 'submitted';
  const snapshot = report.report_snapshot;
  const sectionComments = review.comments.filter((c) => c.section_key === activeSection);
  const showSupportingMedia = activeSection === 'signals' || activeSection === 'patterns';

  const sidebarMedia = useMemo(() => {
    if (!showSupportingMedia) return [];
    const snapshotMedia = (snapshot.supporting_media as { id: number }[] | undefined) || [];
    const snapshotIds = new Set(snapshotMedia.map((item) => item.id));
    if (snapshotIds.size > 0) {
      return companyMedia.filter((attachment) => snapshotIds.has(attachment.id));
    }
    return companyMedia;
  }, [companyMedia, showSupportingMedia, snapshot.supporting_media]);

  return (
    <div className="space-y-6">
      <PageHeader
        title="Report review"
        description={`Status: ${review.status}${review.submitted_at ? ` · submitted ${new Date(review.submitted_at).toLocaleString()}` : ''}`}
        breadcrumbs={[
          { label: 'Dashboard', href: '/reviewer/dashboard' },
          { label: 'Company', href: `/reviewer/companies/${companyId}` },
          { label: 'Review' },
        ]}
        actions={
          !submitted ? (
            <Button onClick={submitReview}>Submit review</Button>
          ) : (
            <Badge variant="success">Submitted</Badge>
          )
        }
      />

      <div className="grid gap-6 lg:grid-cols-12">
        {/* Section nav */}
        <nav className="lg:col-span-2">
          <Card padding={false} className="p-2">
            <ul className="m-0 list-none p-2">
              {SECTIONS.map((key) => {
                const state = review.section_states.find((s) => s.section_key === key)?.status || 'not_started';
                return (
                  <li key={key}>
                    <button
                      type="button"
                      onClick={() => setActiveSection(key)}
                      className={cn(
                        'w-full rounded-button px-3 py-2 text-left text-sm transition-colors',
                        activeSection === key
                          ? 'bg-accent-muted font-medium text-accent'
                          : 'text-text-secondary hover:bg-surface-muted hover:text-text-primary'
                      )}
                    >
                      <span className="block capitalize">{key.replace(/_/g, ' ')}</span>
                      <span className="text-xs opacity-70">{state.replace(/_/g, ' ')}</span>
                    </button>
                  </li>
                );
              })}
            </ul>
          </Card>
          <Card title="Overall note" className="mt-4">
            <Textarea rows={4} value={note} disabled={submitted} onChange={(e) => setNote(e.target.value)} />
            {!submitted && (
              <Button variant="secondary" size="sm" className="mt-2" onClick={saveNote}>
                Save note
              </Button>
            )}
          </Card>
        </nav>

        {/* Content */}
        <div className="lg:col-span-6">
          <Card title={activeSection.replace(/_/g, ' ')}>
            {!submitted && (
              <div className="mb-4 max-w-xs">
                <Select
                  label="Section status"
                  value={review.section_states.find((s) => s.section_key === activeSection)?.status || 'not_started'}
                  onChange={(e) => setSectionStatus(activeSection, e.target.value)}
                  options={[
                    { value: 'not_started', label: 'Not started' },
                    { value: 'in_progress', label: 'In progress' },
                    { value: 'reviewed', label: 'Reviewed' },
                    { value: 'needs_clarification', label: 'Needs clarification' },
                  ]}
                />
              </div>
            )}
            <SectionContent section={activeSection} snapshot={snapshot} />
          </Card>

          {payload.co_reviewer_reviews.length > 0 && (
            <Card title="Co-reviewer progress" className="mt-4">
              {payload.co_reviewer_reviews.map((cr) => (
                <div key={cr.reviewer_name} className="border-t border-border py-3 first:border-0 first:pt-0">
                  <p className="m-0 text-sm font-medium">
                    {cr.reviewer_name} — <Badge variant="neutral">{cr.status}</Badge>
                  </p>
                  <ul className="mt-2 text-sm text-text-secondary">
                    {cr.comments.map((c, i) => (
                      <li key={i}>
                        {c.section_key}: {c.body}
                      </li>
                    ))}
                  </ul>
                </div>
              ))}
            </Card>
          )}
        </div>

        {/* Comment thread */}
        <aside className="lg:col-span-4">
          <Card title="Comments">
            <ul className="mb-4 max-h-[320px] space-y-3 overflow-y-auto">
              {sectionComments.length === 0 ? (
                <li className="text-sm text-text-secondary">No comments on this section yet.</li>
              ) : (
                sectionComments.map((c) => (
                  <li key={c.id} className="rounded-button border border-border bg-surface-muted p-3 text-sm">
                    <p className="m-0 text-xs text-text-secondary">{c.reviewer_name}</p>
                    <p className="m-0 mt-1 text-text-primary">{c.body}</p>
                  </li>
                ))
              )}
            </ul>
            {!submitted && (
              <form onSubmit={addComment} className="space-y-3">
                <Input
                  value={commentBody}
                  onChange={(e) => setCommentBody(e.target.value)}
                  placeholder="Add a comment on this section…"
                />
                <Button type="submit" variant="secondary" size="sm" disabled={!commentBody.trim()}>
                  Add comment
                </Button>
              </form>
            )}
          </Card>

          {showSupportingMedia && token && (
            <Card title="Supporting media" className="mt-4">
              {sidebarMedia.length === 0 ? (
                <p className="text-sm text-text-secondary">No media shared for this company yet.</p>
              ) : (
                <ConversationMediaList attachments={sidebarMedia} token={token} />
              )}
            </Card>
          )}
        </aside>
      </div>

      <Link to={`/reviewer/companies/${companyId}`} className="text-sm font-medium text-accent hover:underline">
        ← Back to company
      </Link>
    </div>
  );
}
