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
  const [generating, setGenerating] = useState(false);
  const [error, setError] = useState('');
  const [shareMsg, setShareMsg] = useState('');
  const [loading, setLoading] = useState(true);
  const [readiness, setReadiness] = useState<{ score: number; docsFirst: boolean; breakdown: Record<string, number> }>({
    score: 0,
    docsFirst: false,
    breakdown: {},
  });

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

  useEffect(() => {
    if (!token) return;
    api.companyDashboard(token).then((d) => {
      setReadiness({
        score: Math.round(d.report_readiness_score ?? 0),
        docsFirst: Boolean(d.docs_first_phase ?? d.company.docs_first_phase),
        breakdown: d.report_readiness_breakdown ?? {},
      });
    });
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
      const msg = `Share link created (expires ${new Date(res.expires_at).toLocaleDateString()}): ${res.share_url}`;
      setShareMsg(msg);
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
        <p className="mb-3 text-sm text-text-secondary">
          Current readiness: <span className="font-medium text-text-primary">{readiness.score}%</span>
          {readiness.docsFirst
            ? ' (document baseline — need ready docs, department tags, and patterns).'
            : ' (blended document + interview dimensions).'}
          {readiness.score < 100 && readiness.docsFirst && (
            <>
              {' '}
              Ready docs: {readiness.breakdown.ready_documents ?? 0}, departments:{' '}
              {readiness.breakdown.document_departments ?? 0}, patterns:{' '}
              {readiness.breakdown.confirmed_patterns ?? 0}.
            </>
          )}
        </p>
        <Button onClick={generate} loading={generating} disabled={generating}>
          {generating ? 'Generating…' : 'Generate new report'}
        </Button>
        <p className="mt-2 text-sm text-text-secondary">
          {readiness.score >= 100
            ? 'Ready to generate — report will use your current document and interview evidence.'
            : 'Generation unlocks at 100% readiness. Keep uploading tagged documents or completing interviews.'}
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
        emptyState={
          <EmptyState
            title="No reports yet"
            description={
              readiness.score >= 100
                ? 'Generate your first discovery or baseline report.'
                : 'Reach 100% readiness, then generate a versioned report.'
            }
            action={
              readiness.score >= 100
                ? { label: 'Generate report', onClick: () => void generate() }
                : {
                    label: readiness.docsFirst ? 'Upload documents' : 'Check dashboard',
                    onClick: () => navigate(readiness.docsFirst ? '/company/documents' : '/company/dashboard'),
                  }
            }
          />
        }
      />
    </div>
  );
}
