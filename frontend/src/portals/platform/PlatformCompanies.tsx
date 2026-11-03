import { useEffect, useState } from 'react';
import { flushSync } from 'react-dom';
import { Link, useNavigate } from 'react-router-dom';
import { api, type Company } from '../../lib/api';
import { useAuth, usePlatformToken, startImpersonation } from '../../lib/auth';
import { ProgressBar } from '../../components/ui/ProgressBar';
import { PageHeader, Button, DataTable, StatusBadge, EmptyState, Modal } from '../../components/ui';
import { useToast } from '../../components/ui/ToastProvider';
import { EngagementSetupForm } from './EngagementSetupForm';
import { ENGAGEMENT_STATUS_LABELS } from './engagementStatus';

export function PlatformCompanies() {
  const { session, setSession } = useAuth();
  const token = usePlatformToken();
  const navigate = useNavigate();
  const { toast } = useToast();
  const [companies, setCompanies] = useState<Company[]>([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [error, setError] = useState('');
  const [impersonatingId, setImpersonatingId] = useState<number | null>(null);

  const load = () => {
    if (!token) return;
    setLoading(true);
    setError('');
    api
      .platformCompanies(token)
      .then((d) => setCompanies(d.companies))
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load companies'))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
  }, [token]);

  const handleImpersonate = async (companyId: number) => {
    if (!token || session?.portal !== 'platform') return;
    setImpersonatingId(companyId);
    setError('');
    try {
      const res = await api.impersonateCompany(token, companyId);
      flushSync(() => {
        startImpersonation(setSession, session, {
          token: res.token,
          user: { ...res.user, onboarding_completed_at: null },
          company: {
            id: res.company.id,
            name: res.company.display_name || res.company.name,
            portal_onboarding_completed_at: res.company.portal_onboarding_completed_at,
          },
        });
      });
      navigate('/company/dashboard');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Impersonation failed');
    } finally {
      setImpersonatingId(null);
    }
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="Companies"
        description="Set up client engagements and manage client organizations."
        actions={
          <Button onClick={() => setShowForm(true)}>New engagement</Button>
        }
      />

      {error && (
        <p className="text-sm text-destructive">
          {error}
          {error.toLowerCase().includes('unauthorized') && (
            <> — try logging out and signing in again at <a href="/platform/login" className="underline">/platform/login</a>.</>
          )}
        </p>
      )}

      <DataTable
        loading={loading}
        columns={[
          {
            key: 'name',
            header: 'Company',
            render: (c) => (
              <div>
                <Link
                  to={`/platform/companies/${c.id}`}
                  className="font-medium text-primary hover:underline"
                  onClick={(e) => e.stopPropagation()}
                >
                  {c.display_name || c.name}
                </Link>
                <p className="m-0 text-xs text-muted-foreground">{c.slug}</p>
              </div>
            ),
          },
          {
            key: 'readiness',
            header: 'Readiness',
            render: (c) => (
              <div className="flex min-w-[120px] flex-col gap-1">
                <span className="text-xs font-medium tabular-nums text-foreground">
                  {Math.round(c.report_readiness_score)}%
                </span>
                <ProgressBar value={c.report_readiness_score} size="sm" />
              </div>
            ),
          },
          {
            key: 'engagement',
            header: 'Engagement',
            render: (c) => (c.engagement_status ? ENGAGEMENT_STATUS_LABELS[c.engagement_status] : '—'),
          },
          {
            key: 'onboarding',
            header: 'Onboarding',
            render: (c) => (
              <StatusBadge status={c.portal_onboarding_completed_at ? 'complete' : 'pending'} />
            ),
          },
          {
            key: 'actions',
            header: '',
            className: 'text-right',
            render: (c) => (
              <div className="flex justify-end gap-2" onClick={(e) => e.stopPropagation()}>
                <Button
                  variant="secondary"
                  size="sm"
                  loading={impersonatingId === c.id}
                  onClick={() => handleImpersonate(c.id)}
                >
                  Impersonate
                </Button>
              </div>
            ),
          },
        ]}
        rows={companies as Company[]}
        onRowClick={(c) => navigate(`/platform/companies/${c.id}`)}
        emptyState={<EmptyState title="No companies" description="Set up your first client engagement." />}
      />

      <Modal open={showForm} onClose={() => setShowForm(false)} title="New engagement" className="max-w-2xl">
        {showForm && token && (
          <EngagementSetupForm
            token={token}
            submitLabel="Create and invite"
            onCancel={() => setShowForm(false)}
            onSubmit={async (input) => {
              const { engagement } = await api.createEngagement(token, input);
              setShowForm(false);
              toast({ title: `Invitation sent to ${engagement.key_user?.email ?? 'the key user'}`, variant: 'success' });
              navigate(`/platform/companies/${engagement.company_id}`);
            }}
          />
        )}
      </Modal>
    </div>
  );
}
