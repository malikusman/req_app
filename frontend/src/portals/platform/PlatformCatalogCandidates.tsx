import { useEffect, useState } from 'react';
import { api } from '../../lib/api';
import { usePlatformToken } from '../../lib/auth';
import { PageHeader, Card, DataTable, Badge, Button, EmptyState, Textarea } from '../../components/ui';

type Candidate = {
  id: number;
  name: string;
  vendor?: string;
  entity_type?: string;
  description?: string;
  website_url?: string;
  confidence?: number;
  review_status: string;
  provenance?: Record<string, unknown>;
};

export function PlatformCatalogCandidates() {
  const token = usePlatformToken();
  const [candidates, setCandidates] = useState<Candidate[]>([]);
  const [note, setNote] = useState('');
  const [loading, setLoading] = useState(true);
  const [actingId, setActingId] = useState<number | null>(null);

  const load = () => {
    if (!token) return;
    api
      .platformCatalogCandidates(token, 'pending')
      .then((d) => setCandidates(d.catalog_candidates as Candidate[]))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
  }, [token]);

  const act = async (id: number, action: 'approve' | 'reject') => {
    if (!token) return;
    setActingId(id);
    try {
      if (action === 'approve') await api.approveCatalogCandidate(token, id, { review_note: note });
      else await api.rejectCatalogCandidate(token, id, { review_note: note });
      setNote('');
      load();
    } finally {
      setActingId(null);
    }
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="Market candidates"
        description="Approve discovered catalog entries before they become matchable recommendations."
      />
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
              <div>
                <div className="font-medium">{c.name}</div>
                <div className="text-xs text-text-secondary">
                  {[c.vendor, c.entity_type].filter(Boolean).join(' · ') || '—'}
                </div>
              </div>
            ),
          },
          {
            key: 'confidence',
            header: 'Confidence',
            render: (c: Candidate) => (typeof c.confidence === 'number' ? c.confidence.toFixed(2) : '—'),
          },
          {
            key: 'status',
            header: 'Status',
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
        emptyState={<EmptyState title="No pending candidates" description="Market discovery candidates awaiting curation will appear here." />}
      />
    </div>
  );
}
