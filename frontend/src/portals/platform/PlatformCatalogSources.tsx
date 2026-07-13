import { useEffect, useState } from 'react';
import { api } from '../../lib/api';
import { usePlatformToken } from '../../lib/auth';
import { PageHeader, Card, DataTable, Badge, Button, EmptyState, Input } from '../../components/ui';

type CatalogSource = {
  id: number;
  name: string;
  source_type: string;
  endpoint_url?: string | null;
  active: boolean;
  trust_score?: number;
  last_sync_at?: string | null;
  last_sync_status?: string | null;
};

export function PlatformCatalogSources() {
  const token = usePlatformToken();
  const [sources, setSources] = useState<CatalogSource[]>([]);
  const [intervalHours, setIntervalHours] = useState(12);
  const [name, setName] = useState('');
  const [endpointUrl, setEndpointUrl] = useState('');
  const [sourceType, setSourceType] = useState('rss');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [syncingId, setSyncingId] = useState<number | null>(null);
  const [syncingAll, setSyncingAll] = useState(false);
  const [error, setError] = useState('');
  const [message, setMessage] = useState('');

  const load = () => {
    if (!token) return;
    api
      .platformCatalogSources(token)
      .then((d) => {
        setSources(d.catalog_sources as CatalogSource[]);
        if (typeof d.sync_interval_hours === 'number') setIntervalHours(d.sync_interval_hours);
      })
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load sources'))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
  }, [token]);

  const create = async () => {
    if (!token || !name.trim()) return;
    setSaving(true);
    setError('');
    setMessage('');
    try {
      await api.createPlatformCatalogSource(token, {
        name: name.trim(),
        source_type: sourceType,
        endpoint_url: endpointUrl.trim() || undefined,
        active: true,
        trust_score: 0.5,
      });
      setName('');
      setEndpointUrl('');
      setMessage('Source created.');
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Create failed');
    } finally {
      setSaving(false);
    }
  };

  const toggleActive = async (source: CatalogSource) => {
    if (!token) return;
    setError('');
    try {
      await api.updatePlatformCatalogSource(token, source.id, { active: !source.active });
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Update failed');
    }
  };

  const syncOne = async (id: number) => {
    if (!token) return;
    setSyncingId(id);
    setError('');
    setMessage('');
    try {
      const res = await api.syncPlatformCatalogSource(token, id);
      const run = res.catalog_sync_run as { status?: string; candidates_created?: number };
      setMessage(`Sync ${run?.status || 'done'} — candidates created: ${run?.candidates_created ?? 0}`);
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Sync failed');
    } finally {
      setSyncingId(null);
    }
  };

  const syncAll = async () => {
    if (!token) return;
    setSyncingAll(true);
    setError('');
    setMessage('');
    try {
      await api.syncAllCatalogSources(token);
      setMessage('All-source sync enqueued.');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Enqueue failed');
    } finally {
      setSyncingAll(false);
    }
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="Catalog sources"
        description={`RSS/API feeds that seed market candidates. Scheduled every ${intervalHours}h (AI_CATALOG_SYNC_INTERVAL_HOURS).`}
        actions={
          <Button size="sm" variant="secondary" loading={syncingAll} onClick={syncAll}>
            Sync all now
          </Button>
        }
      />

      {error && <p className="text-sm text-status-error">{error}</p>}
      {message && <p className="text-sm text-text-secondary">{message}</p>}

      <Card title="Add source">
        <div className="grid gap-3 md:grid-cols-2">
          <Input label="Name" value={name} onChange={(e) => setName(e.target.value)} placeholder="TechCrunch AI RSS" />
          <Input
            label="Endpoint URL (RSS/Atom)"
            value={endpointUrl}
            onChange={(e) => setEndpointUrl(e.target.value)}
            placeholder="https://example.com/feed.xml"
          />
          <div>
            <label className="mb-1.5 block text-sm font-medium">Source type</label>
            <select
              className="w-full rounded-md border border-border bg-background px-3 py-2 text-sm"
              value={sourceType}
              onChange={(e) => setSourceType(e.target.value)}
            >
              <option value="rss">rss</option>
              <option value="api">api</option>
              <option value="manual_feed">manual_feed</option>
              <option value="scrape">scrape</option>
            </select>
          </div>
        </div>
        <div className="mt-4">
          <Button size="sm" loading={saving} disabled={!name.trim()} onClick={create}>
            Create source
          </Button>
        </div>
      </Card>

      <DataTable
        loading={loading}
        columns={[
          {
            key: 'name',
            header: 'Source',
            render: (s: CatalogSource) => (
              <div>
                <div className="font-medium">{s.name}</div>
                <div className="text-xs text-text-secondary">{s.endpoint_url || 'No endpoint (stub sync)'}</div>
              </div>
            ),
          },
          { key: 'source_type', header: 'Type', render: (s: CatalogSource) => s.source_type },
          {
            key: 'active',
            header: 'Active',
            render: (s: CatalogSource) => (
              <Badge variant={s.active ? 'success' : 'neutral'}>{s.active ? 'active' : 'paused'}</Badge>
            ),
          },
          {
            key: 'last',
            header: 'Last sync',
            render: (s: CatalogSource) => (
              <span className="text-xs text-text-secondary">
                {s.last_sync_status || '—'}
                {s.last_sync_at ? ` · ${new Date(s.last_sync_at).toLocaleString()}` : ''}
              </span>
            ),
          },
          {
            key: 'actions',
            header: '',
            render: (s: CatalogSource) => (
              <div className="flex flex-wrap gap-2">
                <Button size="sm" loading={syncingId === s.id} onClick={() => syncOne(s.id)}>
                  Sync
                </Button>
                <Button size="sm" variant="secondary" onClick={() => toggleActive(s)}>
                  {s.active ? 'Pause' : 'Activate'}
                </Button>
              </div>
            ),
          },
        ]}
        rows={sources}
        emptyState={<EmptyState title="No sources" description="Add an RSS feed to discover market tools as candidates." />}
      />
    </div>
  );
}
