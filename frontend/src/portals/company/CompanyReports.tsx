import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api, type Report } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { PageHeader, Card, Button, DataTable, Badge, EmptyState } from '../../components/ui';
import { CompanyExpertReviewers } from './CompanyExpertReviewers';
import { useToast } from '../../components/ui/ToastProvider';

export function CompanyReports() {
  const token = useCompanyToken();
  const navigate = useNavigate();
  const { toast } = useToast();
  const [reports, setReports] = useState<Report[]>([]);
  const [error, setError] = useState('');
  const [loadError, setLoadError] = useState('');
  const [loading, setLoading] = useState(true);

  const load = () => {
    if (!token) return;
    api
      .companyReports(token)
      .then((d) => {
        setReports(d.reports);
        setLoadError('');
      })
      .catch(() => setLoadError('Could not load reports.'))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
    const interval = setInterval(load, 5000);
    return () => clearInterval(interval);
  }, [token]);

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

  return (
    <div className="space-y-6">
      <PageHeader
        title="Reports"
        description="Reports shared with your company by your reviewer or platform. Download or create an external share link."
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

      <CompanyExpertReviewers />

      <Card>
        <p className="m-0 text-sm text-text-secondary">
          Company admins can view and download shared reports. Report generation is handled by your assigned
          reviewer and platform team.
        </p>
      </Card>

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
            header: 'Delta',
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
            key: 'review',
            header: 'Availability',
            render: () => <Badge variant="success">Shared</Badge>,
          },
          {
            key: 'actions',
            header: '',
            render: (r) =>
              r.status === 'ready' ? (
                <div className="flex gap-2">
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
    </div>
  );
}
