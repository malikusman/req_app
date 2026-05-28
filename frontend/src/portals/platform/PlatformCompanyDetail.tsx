import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { api, type Company, type PlatformReport } from '../../lib/api';
import { usePlatformToken } from '../../lib/auth';
import {
  PageHeader,
  Tabs,
  Card,
  Badge,
  DataTable,
  EmptyState,
  Button,
  Skeleton,
} from '../../components/ui';
import { PlatformCompanyReviewers } from './PlatformCompanyReviewers';
import { mockAuditLogs } from '../../lib/mocks/platformAuditLog';

function workflowLabel(report: PlatformReport) {
  if (report.visibility === 'shared_with_company') return { text: 'Released to client', variant: 'success' as const };
  if (report.review_workflow_status === 'reviews_complete') return { text: 'Ready to release', variant: 'info' as const };
  if (report.review_workflow_status === 'awaiting_reviewers' || report.review_workflow_status === 'in_review') {
    return { text: 'In expert review', variant: 'warning' as const };
  }
  return { text: 'Internal only', variant: 'neutral' as const };
}

function signOffBadge(status: string) {
  if (status === 'submitted') return <Badge variant="success">Submitted</Badge>;
  if (status === 'ready') return <Badge variant="info">Ready from their side</Badge>;
  return <Badge variant="neutral">Pending</Badge>;
}

export function PlatformCompanyDetail() {
  const { id } = useParams();
  const companyId = Number(id);
  const token = usePlatformToken();
  const [company, setCompany] = useState<Company | null>(null);
  const [reports, setReports] = useState<PlatformReport[]>([]);
  const [hasActiveReviewers, setHasActiveReviewers] = useState(true);
  const [tab, setTab] = useState('overview');
  const [loading, setLoading] = useState(true);
  const [actionError, setActionError] = useState('');
  const [actionLoading, setActionLoading] = useState<number | null>(null);

  const loadReports = () => {
    if (!token || !companyId) return;
    api.platformCompanyReports(token, companyId).then((r) => {
      setReports(r.reports);
      setHasActiveReviewers(r.has_active_reviewers);
    });
  };

  useEffect(() => {
    if (!token || !companyId) return;
    setLoading(true);
    Promise.all([
      api.platformCompanies(token).then((d) => d.companies.find((c) => c.id === companyId) ?? null),
      api.platformCompanyReports(token, companyId).catch(() => ({ reports: [] as PlatformReport[], has_active_reviewers: false })),
    ])
      .then(([c, r]) => {
        setCompany(c);
        setReports(r.reports);
        setHasActiveReviewers(r.has_active_reviewers);
      })
      .finally(() => setLoading(false));
  }, [token, companyId]);

  const generateReport = async () => {
    if (!token) return;
    setActionError('');
    setActionLoading(-1);
    try {
      await api.generatePlatformReport(token, companyId);
      loadReports();
    } catch (err) {
      setActionError(err instanceof Error ? err.message : 'Generate failed');
    } finally {
      setActionLoading(null);
    }
  };

  const releaseReport = async (reportId: number) => {
    if (!token) return;
    if (!window.confirm('Release this report to the company portal? The client admin will be able to view and share it.')) return;
    setActionError('');
    setActionLoading(reportId);
    try {
      await api.releasePlatformReport(token, companyId, reportId);
      loadReports();
    } catch (err) {
      setActionError(err instanceof Error ? err.message : 'Release failed');
    } finally {
      setActionLoading(null);
    }
  };

  const canRelease = (r: PlatformReport) =>
    r.status === 'ready' &&
    r.visibility !== 'shared_with_company' &&
    (r.review_workflow_status === 'reviews_complete' || !hasActiveReviewers);

  if (loading) {
    return (
      <div className="space-y-6">
        <Skeleton variant="text" />
        <Skeleton variant="card" />
      </div>
    );
  }

  if (!company) {
    return <EmptyState title="Company not found" description="This company may have been removed." />;
  }

  const name = company.display_name || company.name;

  return (
    <div className="space-y-6">
      <PageHeader
        title={name}
        description={company.slug}
        breadcrumbs={[
          { label: 'Companies', href: '/platform/companies' },
          { label: name },
        ]}
        actions={
          <Link to="/platform/companies">
            <Button variant="secondary">Back</Button>
          </Link>
        }
      />

      <Tabs
        tabs={[
          { value: 'overview', label: 'Overview' },
          { value: 'conversations', label: 'Conversations' },
          { value: 'intelligence', label: 'Intelligence' },
          { value: 'reports', label: 'Reports' },
          { value: 'reviewers', label: 'Reviewers' },
          { value: 'audit', label: 'Audit' },
        ]}
        value={tab}
        onChange={setTab}
      />

      {tab === 'overview' && (
        <div className="grid gap-4 md:grid-cols-3">
          <Card title="Readiness">
            <p className="m-0 text-3xl font-semibold text-text-primary">{Math.round(company.report_readiness_score)}%</p>
          </Card>
          <Card title="Subscription">
            <p className="m-0 text-sm text-text-primary">
              {company.subscription ? `${company.subscription.plan} · ${company.subscription.status}` : 'None'}
            </p>
          </Card>
          <Card title="Onboarding">
            <Badge variant={company.portal_onboarding_completed_at ? 'success' : 'warning'}>
              {company.portal_onboarding_completed_at ? 'Complete' : 'Pending'}
            </Badge>
          </Card>
        </div>
      )}

      {tab === 'conversations' && (
        <EmptyState
          title="No conversations"
          description="Conversation data will appear here when employees start discovery interviews."
        />
      )}

      {tab === 'intelligence' && (
        <EmptyState
          title="Intelligence preview"
          description="Platform-level intelligence views are coming soon. Use the company portal for live signals."
        />
      )}

      {tab === 'reports' && (
        <div className="space-y-4">
          {actionError && <p className="text-sm text-status-error">{actionError}</p>}

          {!hasActiveReviewers && (
            <div className="rounded-button border border-accent/30 bg-surface-muted px-4 py-3 text-sm text-text-primary">
              No expert reviewers assigned — you can generate, review, and release reports directly to the client.
            </div>
          )}

          <Card>
            <div className="flex flex-wrap items-center justify-between gap-3">
              <p className="m-0 text-sm text-text-secondary">
                Reports stay internal until you release them. Reviewers sign off first when assigned.
              </p>
              <Button onClick={generateReport} loading={actionLoading === -1}>
                Generate report
              </Button>
            </div>
          </Card>

          <DataTable
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
                key: 'workflow',
                header: 'Release',
                render: (r) => {
                  const w = workflowLabel(r);
                  return <Badge variant={w.variant}>{w.text}</Badge>;
                },
              },
              {
                key: 'reviewers',
                header: 'Reviewer sign-off',
                render: (r) =>
                  r.reviewer_progress && r.reviewer_progress.length > 0 ? (
                    <ul className="m-0 list-none space-y-1 p-0 text-xs">
                      {r.reviewer_progress.map((rp) => (
                        <li key={rp.reviewer_user_id} className="flex flex-wrap items-center gap-2">
                          <span>{rp.reviewer_name}</span>
                          {signOffBadge(rp.sign_off_status)}
                        </li>
                      ))}
                    </ul>
                  ) : (
                    <span className="text-xs text-text-secondary">—</span>
                  ),
              },
              {
                key: 'generated',
                header: 'Generated',
                render: (r) => (r.generated_at ? new Date(r.generated_at).toLocaleString() : '—'),
              },
              {
                key: 'actions',
                header: '',
                render: (r) =>
                  canRelease(r) ? (
                    <Button
                      size="sm"
                      loading={actionLoading === r.id}
                      onClick={() => releaseReport(r.id)}
                    >
                      Release to client
                    </Button>
                  ) : r.visibility === 'shared_with_company' ? (
                    <Badge variant="success">Released</Badge>
                  ) : null,
              },
            ]}
            rows={reports as PlatformReport[]}
            emptyState={<EmptyState title="No reports" description="Generate a report when discovery is ready." />}
          />
        </div>
      )}

      {tab === 'reviewers' && (
        <PlatformCompanyReviewers companyId={companyId} companyName={name} embedded />
      )}

      {tab === 'audit' && (
        <DataTable
          columns={[
            { key: 'created_at', header: 'When', render: (r) => new Date(r.created_at).toLocaleString() },
            { key: 'actor', header: 'Actor' },
            { key: 'action', header: 'Action' },
            { key: 'target', header: 'Target' },
            { key: 'ip', header: 'IP' },
          ]}
          rows={mockAuditLogs}
          emptyState={<EmptyState title="No audit events" />}
        />
      )}
    </div>
  );
}
