import { useEffect, useState } from 'react';
import { api } from '../../lib/api';
import { usePlatformToken } from '../../lib/auth';
import { PageHeader, Card, DataTable, Badge, Button, EmptyState, Textarea, Select } from '../../components/ui';

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
};

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

  const load = () => {
    if (!token) return;
    setLoading(true);
    api
      .platformCatalogCandidates(token, {
        reviewStatus: reviewStatus || undefined,
        analysisStatus: analysisStatus || undefined,
        entityType: entityType || undefined,
      })
      .then((d) => setCandidates(d.catalog_candidates as Candidate[]))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
  }, [token, reviewStatus, analysisStatus, entityType]);

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
        description="Approve discovered catalog entries before they become matchable recommendations. Analyzed non-stub items can also power employee market alerts."
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

      <DataTable
        loading={loading}
        columns={[
          {
            key: 'name',
            header: 'Candidate',
            render: (c: Candidate) => (
              <button type="button" className="text-left" onClick={() => openDetail(c.id)}>
                <div className="font-medium text-accent hover:underline">{c.name}</div>
                <div className="text-xs text-text-secondary">
                  {[c.vendor, c.entity_type, c.catalog_source_name].filter(Boolean).join(' · ') || '—'}
                </div>
              </button>
            ),
          },
          {
            key: 'analysis',
            header: 'Analysis',
            render: (c: Candidate) => (
              <Badge variant={analysisBadgeVariant(c.analysis_status)}>{c.analysis_status || '—'}</Badge>
            ),
          },
          {
            key: 'provenance',
            header: 'Source',
            render: (c: Candidate) => {
              const url = c.source_url || c.website_url;
              const stub = c.provenance?.stub === true;
              return (
                <div className="max-w-[220px]">
                  {stub ? (
                    <Badge variant="warning">stub</Badge>
                  ) : url ? (
                    <a
                      href={url}
                      target="_blank"
                      rel="noreferrer"
                      className="truncate text-xs text-accent hover:underline"
                      onClick={(e) => e.stopPropagation()}
                    >
                      {url}
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
            render: (c: Candidate) => (typeof c.confidence === 'number' ? c.confidence.toFixed(2) : '—'),
          },
          {
            key: 'status',
            header: 'Review',
            render: (c: Candidate) => <Badge variant="info">{c.review_status}</Badge>,
          },
          {
            key: 'actions',
            header: '',
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

      {selected && (
        <Card
          title={selected.name}
          action={
            <Button size="sm" variant="secondary" onClick={() => setSelected(null)}>
              Close
            </Button>
          }
        >
          <div className="space-y-3 text-sm">
            <div className="flex flex-wrap gap-2">
              <Badge variant={analysisBadgeVariant(selected.analysis_status)}>{selected.analysis_status || '—'}</Badge>
              <Badge variant="info">{selected.review_status}</Badge>
              {selected.entity_type && <Badge variant="neutral">{selected.entity_type}</Badge>}
              {selected.provenance?.stub === true && <Badge variant="warning">stub (not emailable)</Badge>}
            </div>
            <p className="text-text-secondary">{selected.summary || selected.description || 'No summary yet.'}</p>
            {(selected.source_url || selected.website_url) && (
              <p>
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
        </Card>
      )}
    </div>
  );
}
