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

export function PlatformCompanyDetail() {
  const { id } = useParams();
  const companyId = Number(id);
  const token = usePlatformToken();
  const [company, setCompany] = useState<Company | null>(null);
  const [reports, setReports] = useState<PlatformReport[]>([]);
  const [tab, setTab] = useState('overview');
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!token || !companyId) return;
    setLoading(true);
    Promise.all([
      api.platformCompanies(token).then((d) => d.companies.find((c) => c.id === companyId) ?? null),
      api.platformCompanyReports(token, companyId).catch(() => ({ reports: [] as PlatformReport[] })),
    ])
      .then(([c, r]) => {
        setCompany(c);
        setReports(r.reports);
      })
      .finally(() => setLoading(false));
  }, [token, companyId]);

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
              key: 'review',
              header: 'Review',
              render: (r) => String(r.review_workflow_status || '—'),
            },
            {
              key: 'generated',
              header: 'Generated',
              render: (r) => (r.generated_at ? new Date(r.generated_at).toLocaleString() : '—'),
            },
          ]}
          rows={reports as PlatformReport[]}
          emptyState={<EmptyState title="No reports" description="This company has not generated a report yet." />}
        />
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
