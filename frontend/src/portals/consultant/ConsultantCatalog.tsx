import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { api, type SolutionCatalogEntry } from '../../lib/api';
import { useConsultantToken } from '../../lib/auth';
import { PageHeader, Card, Badge, Button, EmptyState, Skeleton, Textarea } from '../../components/ui';

type Match = {
  id: number;
  score?: number;
  matched_at?: string;
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
  consultant_name?: string;
  created_at: string;
};

export function ConsultantCatalog() {
  const { companyId } = useParams();
  const token = useConsultantToken();
  const [matches, setMatches] = useState<Match[]>([]);
  const [endorsements, setEndorsements] = useState<Endorsement[]>([]);
  const [lastMatchedAt, setLastMatchedAt] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [actingId, setActingId] = useState<number | null>(null);
  const [rationale, setRationale] = useState<Record<number, string>>({});
  const [message, setMessage] = useState('');

  const load = () => {
    if (!token || !companyId) return;
    setLoading(true);
    api
      .consultantCatalog(token, Number(companyId))
      .then((d) => {
        setMatches((d.matches || []) as Match[]);
        setEndorsements((d.endorsements || []) as Endorsement[]);
        setLastMatchedAt((d as { last_matched_at?: string | null }).last_matched_at || null);
      })
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load catalog'))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
  }, [token, companyId]);

  // --- Add a product from the catalog to this company's list ---
  const [available, setAvailable] = useState<SolutionCatalogEntry[]>([]);
  const [showAdd, setShowAdd] = useState(false);
  const [query, setQuery] = useState('');
  const [addingId, setAddingId] = useState<number | null>(null);

  const loadAvailable = (q?: string) => {
    if (!token || !companyId) return;
    api
      .consultantAvailableCatalog(token, Number(companyId), q)
      .then((d) => setAvailable(d.solutions || []))
      .catch(() => setAvailable([]));
  };

  const openAdd = () => {
    setShowAdd(true);
    loadAvailable();
  };

  const addProduct = async (entryId: number) => {
    if (!token || !companyId) return;
    setAddingId(entryId);
    setError('');
    setMessage('');
    try {
      await api.consultantAddCatalogProduct(token, Number(companyId), { solution_catalog_entry_id: entryId });
      setMessage('Product added to this company’s list.');
      loadAvailable(query);
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Add failed');
    } finally {
      setAddingId(null);
    }
  };

  const endorse = async (matchId: number, disposition: 'endorse' | 'reject' | 'suggest') => {
    if (!token || !companyId) return;
    setActingId(matchId);
    setError('');
    setMessage('');
    try {
      await api.endorseConsultantCatalogMatch(token, Number(companyId), matchId, {
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
        description="Promoted solutions matched to this company (not the live web scrape queue). Endorse items to publish into the report tools section."
        breadcrumbs={[
          { label: 'Dashboard', href: '/consultant/dashboard' },
          { label: 'Company', href: `/consultant/companies/${companyId}` },
          { label: 'Catalog' },
        ]}
      />

      {error && <p className="text-sm text-status-error">{error}</p>}
      {message && (
        <p className="rounded-button bg-status-successBg px-4 py-2 text-sm text-status-success">{message}</p>
      )}

      <p className="m-0 text-sm text-muted-foreground">
        Platform curates new tools from the web; after approval they are rematched here for this company.
        {lastMatchedAt ? ` Last matched ${new Date(lastMatchedAt).toLocaleString()}.` : ''}
      </p>

      <Card
        title="Add a product to this company"
        action={
          <Button variant="secondary" size="sm" onClick={() => (showAdd ? setShowAdd(false) : openAdd())}>
            {showAdd ? 'Close' : 'Add product'}
          </Button>
        }
      >
        {showAdd ? (
          <div className="space-y-3">
            <input
              type="text"
              value={query}
              onChange={(e) => {
                setQuery(e.target.value);
                loadAvailable(e.target.value);
              }}
              placeholder="Search the catalog…"
              className="w-full rounded-button border border-border bg-white px-3 py-2 text-sm"
            />
            {available.length === 0 ? (
              <p className="text-sm text-text-secondary">No matching catalog products available to add.</p>
            ) : (
              <ul className="max-h-72 space-y-2 overflow-y-auto">
                {available.map((s) => (
                  <li
                    key={s.id}
                    className="flex items-start justify-between gap-3 rounded-md border border-border px-3 py-2"
                  >
                    <div className="min-w-0">
                      <div className="flex items-center gap-2">
                        <span className="truncate text-sm font-medium text-text-primary">{s.name}</span>
                        {s.first_party && <Badge variant="success">Worktruth product</Badge>}
                        {s.vendor && <span className="text-xs text-text-secondary">{s.vendor}</span>}
                      </div>
                      {s.description && (
                        <p className="mt-0.5 line-clamp-2 text-xs text-text-secondary">{s.description}</p>
                      )}
                    </div>
                    <Button
                      size="sm"
                      loading={addingId === s.id}
                      disabled={addingId === s.id}
                      onClick={() => addProduct(s.id)}
                    >
                      Add
                    </Button>
                  </li>
                ))}
              </ul>
            )}
          </div>
        ) : (
          <p className="text-sm text-text-secondary">
            Attach a product from the catalog (first-party or third-party) as a recommended fit for this company. It
            appears in the report tools section, tagged as consultant-added.
          </p>
        )}
      </Card>
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
                      {m.matched_at ? ` · matched ${new Date(m.matched_at).toLocaleDateString()}` : ''}
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
            <Link to={`/consultant/companies/${companyId}`} className="text-xs text-primary hover:underline">
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
