import { useEffect, useState } from 'react';
import { api } from '../../lib/api';
import { usePlatformToken } from '../../lib/auth';
import { PageHeader, Card, DataTable, Badge, Button, EmptyState, Textarea, Select, Modal } from '../../components/ui';

type Candidate = {
  id: number;
  name: string;
  vendor?: string;
  entity_type?: string;
  description?: string;
  summary?: string;
  website_url?: string;
  source_url?: string;
  confidence?: number;
  review_status: string;
  analysis_status?: string;
  catalog_source_name?: string;
  topics?: string[];
  industries?: string[];
  provenance?: Record<string, unknown>;
  created_at?: string;
};

const PER_PAGE = 30;

const reviewOptions = [
  { value: 'pending', label: 'Pending review' },
  { value: 'approved', label: 'Approved' },
  { value: 'rejected', label: 'Rejected' },
  { value: 'merged', label: 'Merged' },
  { value: '', label: 'All reviews' },
];

const analysisOptions = [
  { value: '', label: 'All analysis' },
  { value: 'pending', label: 'Pending' },
  { value: 'analyzed', label: 'Analyzed' },
  { value: 'stale', label: 'Stale' },
  { value: 'archived', label: 'Archived' },
];

const entityOptions = [
  { value: '', label: 'All types' },
  { value: 'tool', label: 'Tool' },
  { value: 'news', label: 'News' },
  { value: 'model', label: 'Model' },
  { value: 'other', label: 'Other' },
];

function analysisBadgeVariant(status?: string): 'info' | 'success' | 'warning' | 'neutral' {
  switch (status) {
    case 'analyzed':
      return 'success';
    case 'stale':
      return 'warning';
    case 'pending':
      return 'info';
    default:
      return 'neutral';
  }
}

function confidenceLabel(confidence?: number): string {
  if (typeof confidence !== 'number' || Number.isNaN(confidence)) return '—';
  const pct = Math.round((confidence <= 1 ? confidence : confidence / 100) * 100);
  return `${pct}%`;
}

export function PlatformCatalogCandidates() {
  const token = usePlatformToken();
  const [candidates, setCandidates] = useState<Candidate[]>([]);
  const [selected, setSelected] = useState<Candidate | null>(null);
  const [note, setNote] = useState('');
  const [loading, setLoading] = useState(true);
  const [actingId, setActingId] = useState<number | null>(null);
  const [reviewStatus, setReviewStatus] = useState('pending');
  const [analysisStatus, setAnalysisStatus] = useState('');
  const [entityType, setEntityType] = useState('');
  const [page, setPage] = useState(1);
  const [total, setTotal] = useState(0);
  const [error, setError] = useState('');

  const load = () => {
    if (!token) return;
    setLoading(true);
    setError('');
    api
      .platformCatalogCandidates(token, {
        reviewStatus: reviewStatus || undefined,
        analysisStatus: analysisStatus || undefined,
        entityType: entityType || undefined,
        page,
        perPage: PER_PAGE,
      })
      .then((d) => {
        setCandidates(d.catalog_candidates as Candidate[]);
        setTotal(d.pagination?.total ?? 0);
      })
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load candidates'))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
  }, [token, reviewStatus, analysisStatus, entityType, page]);

  useEffect(() => {
    setPage(1);
  }, [reviewStatus, analysisStatus, entityType]);

  const totalPages = Math.max(1, Math.ceil(total / PER_PAGE));
  const rangeStart = total === 0 ? 0 : (page - 1) * PER_PAGE + 1;
  const rangeEnd = Math.min(page * PER_PAGE, total);

  const openDetail = async (id: number) => {
    if (!token) return;
    try {
      const res = await api.platformCatalogCandidate(token, id);
      setSelected(res.catalog_candidate as Candidate);
    } catch {
      setSelected(candidates.find((c) => c.id === id) || null);
    }
  };

  const act = async (id: number, action: 'approve' | 'reject') => {
    if (!token) return;
    setActingId(id);
    try {
      if (action === 'approve') await api.approveCatalogCandidate(token, id, { review_note: note });
      else await api.rejectCatalogCandidate(token, id, { review_note: note });
      setNote('');
      setSelected(null);
      load();
    } finally {
      setActingId(null);
    }
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="Market candidates"
        description="Approve discovered catalog entries before they become matchable recommendations. Confidence is how sure analysis is about the item’s type and relevance (0–100%), not employee fit. Sorted newest first."
      />

      <Card title="Filters">
        <div className="grid gap-3 md:grid-cols-3">
          <Select
            label="Review status"
            options={reviewOptions}
            value={reviewStatus}
            onChange={(e) => setReviewStatus(e.target.value)}
          />
          <Select
            label="Analysis"
            options={analysisOptions}
            value={analysisStatus}
            onChange={(e) => setAnalysisStatus(e.target.value)}
          />
          <Select
            label="Entity type"
            options={entityOptions}
            value={entityType}
            onChange={(e) => setEntityType(e.target.value)}
          />
        </div>
      </Card>

      <Card title="Review note (optional)">
        <Textarea rows={3} value={note} onChange={(e) => setNote(e.target.value)} placeholder="Curation note for the audit trail" />
      </Card>

      {error && (
        <p className="m-0 text-sm text-status-error">
          {error}{' '}
          <button type="button" className="underline" onClick={load}>
            Retry
          </button>
        </p>
      )}

      <DataTable
        loading={loading}
        columns={[
          {
            key: 'name',
            header: 'Candidate',
            className: 'min-w-[12rem] max-w-[16rem] overflow-hidden',
            render: (c: Candidate) => (
              <button type="button" className="max-w-full text-left" onClick={() => openDetail(c.id)}>
                <div className="truncate font-medium text-accent hover:underline">{c.name}</div>
                <div className="truncate text-xs text-text-secondary">
                  {[c.vendor, c.entity_type, c.catalog_source_name].filter(Boolean).join(' · ') || '—'}
                </div>
              </button>
            ),
          },
          {
            key: 'analysis',
            header: 'Analysis',
            className: 'whitespace-nowrap',
            render: (c: Candidate) => (
              <Badge variant={analysisBadgeVariant(c.analysis_status)}>{c.analysis_status || '—'}</Badge>
            ),
          },
          {
            key: 'provenance',
            header: 'Source',
            className: 'max-w-[14rem] overflow-hidden',
            render: (c: Candidate) => {
              const url = c.source_url || c.website_url;
              const stub = c.provenance?.stub === true;
              return (
                <div className="min-w-0 max-w-full overflow-hidden">
                  {stub ? (
                    <Badge variant="warning">stub</Badge>
                  ) : url ? (
                    <a
                      href={url}
                      target="_blank"
                      rel="noreferrer"
                      title={url}
                      className="block truncate text-xs text-accent hover:underline"
                      onClick={(e) => e.stopPropagation()}
                    >
                      {url.replace(/^https?:\/\//, '')}
                    </a>
                  ) : (
                    <span className="text-xs text-text-secondary">—</span>
                  )}
                </div>
              );
            },
          },
          {
            key: 'confidence',
            header: 'Confidence',
            className: 'w-[5.5rem] whitespace-nowrap tabular-nums',
            render: (c: Candidate) => (
              <span className="text-sm text-foreground" title="Analysis confidence that this item is correctly typed and relevant">
                {confidenceLabel(c.confidence)}
              </span>
            ),
          },
          {
            key: 'status',
            header: 'Review',
            className: 'whitespace-nowrap',
            render: (c: Candidate) => <Badge variant="info">{c.review_status}</Badge>,
          },
          {
            key: 'actions',
            header: '',
            className: 'whitespace-nowrap',
            hideOnMobile: false,
            render: (c: Candidate) =>
              c.review_status === 'pending' ? (
                <div className="flex gap-2">
                  <Button size="sm" loading={actingId === c.id} onClick={() => act(c.id, 'approve')}>
                    Approve
                  </Button>
                  <Button size="sm" variant="secondary" loading={actingId === c.id} onClick={() => act(c.id, 'reject')}>
                    Reject
                  </Button>
                </div>
              ) : null,
          },
        ]}
        rows={candidates}
        emptyState={<EmptyState title="No candidates" description="Adjust filters or sync catalog sources to discover market items." />}
      />

      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="m-0 text-sm text-muted-foreground">
          {total === 0 ? 'No results' : `Showing ${rangeStart}–${rangeEnd} of ${total} · newest first`}
        </p>
        <div className="flex items-center gap-2">
          <Button variant="secondary" size="sm" disabled={page <= 1 || loading} onClick={() => setPage((p) => p - 1)}>
            Previous
          </Button>
          <span className="text-sm text-muted-foreground">
            Page {page} of {totalPages}
          </span>
          <Button
            variant="secondary"
            size="sm"
            disabled={page >= totalPages || loading}
            onClick={() => setPage((p) => p + 1)}
          >
            Next
          </Button>
        </div>
      </div>

      <Modal
        open={!!selected}
        onClose={() => setSelected(null)}
        title={selected?.name || 'Candidate'}
        footer={
          <Button size="sm" variant="secondary" onClick={() => setSelected(null)}>
            Close
          </Button>
        }
      >
        {selected && (
          <div className="space-y-3 text-sm">
            <div className="flex flex-wrap gap-2">
              <Badge variant={analysisBadgeVariant(selected.analysis_status)}>{selected.analysis_status || '—'}</Badge>
              <Badge variant="info">{selected.review_status}</Badge>
              {selected.entity_type && <Badge variant="neutral">{selected.entity_type}</Badge>}
              {selected.provenance?.stub === true && <Badge variant="warning">stub (not emailable)</Badge>}
              <Badge variant="neutral">Confidence {confidenceLabel(selected.confidence)}</Badge>
            </div>
            <p className="text-text-secondary">{selected.summary || selected.description || 'No summary yet.'}</p>
            {(selected.source_url || selected.website_url) && (
              <p className="break-all">
                <span className="text-text-secondary">Provenance: </span>
                <a
                  href={selected.source_url || selected.website_url}
                  target="_blank"
                  rel="noreferrer"
                  className="text-accent hover:underline"
                >
                  {selected.source_url || selected.website_url}
                </a>
              </p>
            )}
            {selected.catalog_source_name && (
              <p className="text-text-secondary">Feed: {selected.catalog_source_name}</p>
            )}
            {!!selected.topics?.length && (
              <p className="text-text-secondary">Topics: {selected.topics.join(', ')}</p>
            )}
            {!!selected.industries?.length && (
              <p className="text-text-secondary">Industries: {selected.industries.join(', ')}</p>
            )}
          </div>
        )}
      </Modal>
    </div>
  );
}
