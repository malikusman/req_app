import { useEffect, useState } from 'react';
import { api, type Report } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { PageHeader, Card, Button, DataTable, Badge, EmptyState } from '../../components/ui';
import { CompanyExpertReviewers } from './CompanyExpertReviewers';

export function CompanyReports() {
  const token = useCompanyToken();
  const [reports, setReports] = useState<Report[]>([]);
  const [generating, setGenerating] = useState(false);
  const [error, setError] = useState('');
  const [shareMsg, setShareMsg] = useState('');
  const [loading, setLoading] = useState(true);

  const load = () => {
    if (!token) return;
    api
      .companyReports(token)
      .then((d) => setReports(d.reports))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
    const interval = setInterval(load, 5000);
    return () => clearInterval(interval);
  }, [token]);

  const generate = async () => {
    if (!token) return;
    setError('');
    setGenerating(true);
    try {
      await api.generateReport(token);
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Generate failed');
    } finally {
      setGenerating(false);
    }
  };

  const share = async (id: number) => {
    if (!token) return;
    setShareMsg('');
    try {
      const res = await api.shareReport(token, id, 30);
      setShareMsg(`Share link created (expires ${new Date(res.expires_at).toLocaleDateString()}): ${res.share_url}`);
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Share failed');
    }
  };

  const download = async (id: number) => {
    if (!token) return;
    await api.downloadReport(token, id);
  };

  const canDownloadOrShare = (report: Report) =>
    report.status === 'ready' && report.visibility === 'shared_with_company';

  const reviewStatusLabel = (report: Report) => {
    if (report.visibility === 'shared_with_company') return null;
    if (report.review_workflow_status === 'awaiting_reviewers') return 'Awaiting expert review';
    if (report.review_workflow_status === 'in_review') return 'In expert review';
    if (report.review_workflow_status === 'reviews_complete') return 'Awaiting platform approval';
    if (report.visibility === 'internal_only') return 'Not yet shared';
    return null;
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="Reports"
        description="Generate versioned PDF reports with deltas vs previous versions."
      />

      {error && <p className="text-sm text-status-error">{error}</p>}
      {shareMsg && (
        <p className="rounded-button bg-status-successBg px-4 py-2 text-sm text-status-success">{shareMsg}</p>
      )}

      <CompanyExpertReviewers />

      <Card>
        <Button onClick={generate} loading={generating} disabled={generating}>
          {generating ? 'Generating…' : 'Generate new report'}
        </Button>
        <p className="mt-2 text-sm text-text-secondary">
          Requires readiness score of 100% (or allow_early_report in dev).
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
            render: (r) => {
              const label = reviewStatusLabel(r);
              if (label) return <Badge variant="warning">{label}</Badge>;
              if (r.visibility === 'shared_with_company') return <Badge variant="success">Shared</Badge>;
              return '—';
            },
          },
          {
            key: 'actions',
            header: '',
            render: (r) =>
              r.status === 'ready' && canDownloadOrShare(r) ? (
                <div className="flex gap-2">
                  <Button variant="secondary" size="sm" onClick={() => download(r.id)}>
                    Download
                  </Button>
                  <Button variant="secondary" size="sm" onClick={() => share(r.id)}>
                    Share
                  </Button>
                </div>
              ) : r.status === 'ready' ? (
                <span className="text-xs text-text-secondary">Available after approval</span>
              ) : null,
          },
        ]}
        rows={reports as Report[]}
        emptyState={<EmptyState title="No reports" description="Generate your first discovery report when ready." />}
      />
    </div>
  );
}
