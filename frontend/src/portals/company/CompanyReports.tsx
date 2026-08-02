import { useCallback, useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api, type Report } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { PageHeader, Button, DataTable, Badge, EmptyState, Modal } from '../../components/ui';
import { useToast } from '../../components/ui/ToastProvider';

export function CompanyReports() {
  const token = useCompanyToken();
  const navigate = useNavigate();
  const { toast } = useToast();
  const [reports, setReports] = useState<Report[]>([]);
  const [stale, setStale] = useState(false);
  const [intelUpdatedAt, setIntelUpdatedAt] = useState<string | null>(null);
  const [error, setError] = useState('');
  const [loadError, setLoadError] = useState('');
  const [loading, setLoading] = useState(true);

  // In-portal viewer
  const [viewer, setViewer] = useState<{ report: Report; url: string | null } | null>(null);

  const load = useCallback(() => {
    if (!token) return;
    api
      .companyReports(token)
      .then((d) => {
        setReports(d.reports);
        setStale(d.report_stale === true);
        setIntelUpdatedAt(d.intelligence_updated_at ?? null);
        setLoadError('');
      })
      .catch(() => setLoadError('Could not load reports.'))
      .finally(() => setLoading(false));
  }, [token]);

  useEffect(() => {
    load();
    const interval = setInterval(load, 5000);
    return () => clearInterval(interval);
  }, [load]);

  const openViewer = async (report: Report) => {
    if (!token) return;
    setViewer({ report, url: null });
    try {
      const url = await api.previewCompanyReport(token, report.id);
      setViewer({ report, url });
    } catch {
      setViewer({ report, url: null });
    }
  };

  const closeViewer = () => {
    if (viewer?.url) URL.revokeObjectURL(viewer.url);
    setViewer(null);
  };

  const share = async (id: number) => {
    if (!token) return;
    try {
      const res = await api.shareReport(token, id, 30);
      try {
        await navigator.clipboard.writeText(res.share_url);
        toast({ variant: 'success', title: 'Link copied', description: 'Share URL copied to clipboard.' });
      } catch {
        toast({ variant: 'success', title: 'Share link ready', description: res.share_url });
      }
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Share failed');
    }
  };

  const download = async (id: number) => {
    if (!token) return;
    await api.downloadReport(token, id);
  };

  const generating = reports.some((r) => r.status === 'queued' || r.status === 'generating');

  return (
    <div className="space-y-6">
      <PageHeader
        title="Reports"
        description="View, download, or share the discovery reports your reviewer and platform team prepare for you."
      />

      {error && <p className="text-sm text-status-error">{error}</p>}
      {loadError && (
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-button border border-status-error/30 bg-status-errorBg px-4 py-3 text-sm text-status-error">
          <span>{loadError}</span>
          <Button size="sm" variant="secondary" onClick={load}>
            Retry
          </Button>
        </div>
      )}

      {generating && (
        <div className="rounded-button border border-info/30 bg-info/10 px-4 py-3 text-sm text-info">
          A report is being generated — this page will update automatically when it's ready.
        </div>
      )}

      {stale && !generating && (
        <div className="rounded-button border border-warning/30 bg-warning/10 px-4 py-3 text-sm text-warning">
          Your intelligence has changed
          {intelUpdatedAt && ` (updated ${new Date(intelUpdatedAt).toLocaleString()})`} since your latest report. Ask your
          reviewer or platform team to generate a refreshed version.
        </div>
      )}

      <DataTable
        loading={loading}
        columns={[
          { key: 'version', header: 'Version', render: (r) => `v${r.version}` },
          {
            key: 'status',
            header: 'Status',
            render: (r) => (
              <Badge variant={r.status === 'ready' ? 'success' : r.status === 'failed' ? 'error' : 'info'}>
                {r.status}
              </Badge>
            ),
          },
          {
            key: 'generated',
            header: 'Generated',
            render: (r) => (r.generated_at ? new Date(r.generated_at).toLocaleString() : '—'),
          },
          {
            key: 'delta',
            header: 'What changed',
            render: (r) => <span className="text-xs text-text-secondary">{r.delta_summary || '—'}</span>,
          },
          {
            key: 'views',
            header: 'Share views',
            render: (r) =>
              r.access_count > 0 ? (
                <span className="text-xs text-text-secondary">
                  {r.access_count} views
                  {r.last_accessed_at && ` · last ${new Date(r.last_accessed_at).toLocaleString()}`}
                </span>
              ) : (
                '—'
              ),
          },
          {
            key: 'actions',
            header: '',
            render: (r) =>
              r.status === 'ready' ? (
                <div className="flex gap-2">
                  <Button size="sm" onClick={() => openViewer(r)}>
                    View
                  </Button>
                  <Button variant="secondary" size="sm" onClick={() => download(r.id)}>
                    Download
                  </Button>
                  <Button variant="secondary" size="sm" onClick={() => share(r.id)}>
                    Share
                  </Button>
                </div>
              ) : null,
          },
        ]}
        rows={reports as Report[]}
        emptyState={
          <EmptyState
            title="No shared reports yet"
            description="When your reviewer or platform shares a report with your company, it will appear here."
            action={{
              label: 'Back to dashboard',
              onClick: () => navigate('/company/dashboard'),
            }}
          />
        }
      />

      <Modal
        open={viewer !== null}
        onClose={closeViewer}
        title={viewer ? `Report v${viewer.report.version}` : 'Report'}
        className="sm:max-w-[90vw]"
        footer={
          viewer && (
            <>
              <Button variant="secondary" onClick={() => download(viewer.report.id)}>
                Download
              </Button>
              <Button variant="secondary" onClick={() => share(viewer.report.id)}>
                Share link
              </Button>
              <Button onClick={closeViewer}>Close</Button>
            </>
          )
        }
      >
        {viewer?.url ? (
          <iframe
            src={viewer.url}
            title="Report"
            className="h-[75vh] w-full rounded-lg border border-border bg-white"
          />
        ) : (
          <p className="py-10 text-center text-sm text-text-secondary">Loading report…</p>
        )}
      </Modal>
    </div>
  );
}
