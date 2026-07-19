import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { api } from '../../lib/api';
import { useReviewerToken } from '../../lib/auth';
import { PageHeader, Card, Badge, Button, EmptyState, Skeleton, Textarea } from '../../components/ui';

type Match = {
  id: number;
  score?: number;
  why_it_fits?: string;
  solution_catalog_entry?: {
    id: number;
    name: string;
    vendor?: string;
    category?: string;
    website_url?: string;
    description?: string;
  };
};

type Endorsement = {
  id: number;
  disposition: string;
  rationale?: string;
  solution_name?: string;
  reviewer_name?: string;
  created_at: string;
};

export function ReviewerCatalog() {
  const { companyId } = useParams();
  const token = useReviewerToken();
  const [matches, setMatches] = useState<Match[]>([]);
  const [endorsements, setEndorsements] = useState<Endorsement[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [actingId, setActingId] = useState<number | null>(null);
  const [rationale, setRationale] = useState<Record<number, string>>({});
  const [message, setMessage] = useState('');

  const load = () => {
    if (!token || !companyId) return;
    setLoading(true);
    api
      .reviewerCatalog(token, Number(companyId))
      .then((d) => {
        setMatches((d.matches || []) as Match[]);
        setEndorsements((d.endorsements || []) as Endorsement[]);
      })
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load catalog'))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
  }, [token, companyId]);

  const endorse = async (matchId: number, disposition: 'endorse' | 'reject' | 'suggest') => {
    if (!token || !companyId) return;
    setActingId(matchId);
    setError('');
    setMessage('');
    try {
      await api.endorseReviewerCatalogMatch(token, Number(companyId), matchId, {
        disposition,
        rationale: rationale[matchId]?.trim() || undefined,
        publishable: true,
      });
      setMessage(`Saved ${disposition} for match #${matchId}`);
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Endorse failed');
    } finally {
      setActingId(null);
    }
  };

  if (loading) {
    return (
      <div className="space-y-4">
        <Skeleton variant="text" />
        <Skeleton variant="card" />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="Catalog matches"
        description="Review curated tool matches for this company and add publishable endorsements for the report."
        breadcrumbs={[
          { label: 'Dashboard', href: '/reviewer/dashboard' },
          { label: 'Company', href: `/reviewer/companies/${companyId}` },
          { label: 'Catalog' },
        ]}
      />

      {error && <p className="text-sm text-status-error">{error}</p>}
      {message && (
        <p className="rounded-button bg-status-successBg px-4 py-2 text-sm text-status-success">{message}</p>
      )}

      <div className="grid gap-4 lg:grid-cols-[1fr_320px]">
        <div className="space-y-3">
          {matches.length === 0 ? (
            <EmptyState
              title="No catalog matches"
              description="Matches appear after intelligence aggregation links company signals to the solutions catalog."
            />
          ) : (
            matches.map((m) => {
              const entry = m.solution_catalog_entry;
              return (
                <Card
                  key={m.id}
                  title={entry?.name || `Match #${m.id}`}
                  action={
                    typeof m.score === 'number' ? <Badge variant="info">{m.score.toFixed(2)}</Badge> : undefined
                  }
                >
                  <div className="space-y-3 text-sm">
                    <div className="text-xs text-text-secondary">
                      {[entry?.vendor, entry?.category].filter(Boolean).join(' · ') || '—'}
                    </div>
                    {m.why_it_fits && <p className="m-0">{m.why_it_fits}</p>}
                    {entry?.description && (
                      <p className="m-0 text-xs text-text-secondary">{entry.description}</p>
                    )}
                    {entry?.website_url && (
                      <a className="text-xs text-primary hover:underline" href={entry.website_url} target="_blank" rel="noreferrer">
                        Website
                      </a>
                    )}
                    <Textarea
                      label="Rationale (optional)"
                      rows={2}
                      value={rationale[m.id] || ''}
                      onChange={(e) => setRationale((prev) => ({ ...prev, [m.id]: e.target.value }))}
                      placeholder="Why endorse, reject, or suggest this capability…"
                    />
                    <div className="flex flex-wrap gap-2">
                      <Button size="sm" loading={actingId === m.id} onClick={() => endorse(m.id, 'endorse')}>
                        Endorse
                      </Button>
                      <Button
                        size="sm"
                        variant="secondary"
                        loading={actingId === m.id}
                        onClick={() => endorse(m.id, 'suggest')}
                      >
                        Suggest
                      </Button>
                      <Button
                        size="sm"
                        variant="danger"
                        loading={actingId === m.id}
                        onClick={() => endorse(m.id, 'reject')}
                      >
                        Reject
                      </Button>
                    </div>
                  </div>
                </Card>
              );
            })
          )}
        </div>

        <Card
          title="Recent endorsements"
          action={
            <Link to={`/reviewer/companies/${companyId}`} className="text-xs text-primary hover:underline">
              Company
            </Link>
          }
        >
          {endorsements.length === 0 ? (
            <p className="text-sm text-text-secondary">No endorsements yet.</p>
          ) : (
            <ul className="space-y-2">
              {endorsements.slice(0, 12).map((e) => (
                <li key={e.id} className="rounded-md border border-border p-2 text-xs">
                  <div className="mb-1 flex items-center gap-2">
                    <Badge variant={e.disposition === 'endorse' ? 'success' : e.disposition === 'reject' ? 'error' : 'info'}>
                      {e.disposition}
                    </Badge>
                    <span className="text-text-secondary">{e.solution_name || '—'}</span>
                  </div>
                  {e.rationale && <p className="m-0">{e.rationale}</p>}
                </li>
              ))}
            </ul>
          )}
        </Card>
      </div>
    </div>
  );
}
