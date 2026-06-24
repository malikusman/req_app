import { useEffect, useState } from 'react';
import { flushSync } from 'react-dom';
import { Link, useNavigate } from 'react-router-dom';
import { api, type Company } from '../../lib/api';
import { useAuth, usePlatformToken, startImpersonation } from '../../lib/auth';
import { ProgressBar } from '../../components/ui/ProgressBar';
import {
  PageHeader,
  Button,
  DataTable,
  StatusBadge,
  Input,
  EmptyState,
  Modal,
} from '../../components/ui';
import { Button as OutlineButton } from '@/components/shadcn/button';

export function PlatformCompanies() {
  const { session, setSession } = useAuth();
  const token = usePlatformToken();
  const navigate = useNavigate();
  const [companies, setCompanies] = useState<Company[]>([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [form, setForm] = useState({
    name: '',
    admin_email: '',
    admin_name: '',
    admin_password: 'password123',
  });
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

  const handleCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!token) return;
    setError('');
    try {
      await api.createPlatformCompany(token, {
        name: form.name,
        company_admin: {
          email: form.admin_email,
          name: form.admin_name,
          password: form.admin_password,
        },
      });
      setShowForm(false);
      setForm({ name: '', admin_email: '', admin_name: '', admin_password: 'password123' });
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to create company');
    }
  };

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
        description="Create and manage client organizations."
        actions={
          <Button onClick={() => setShowForm(true)}>New company</Button>
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
            key: 'subscription',
            header: 'Subscription',
            render: (c) =>
              c.subscription ? `${c.subscription.status} · ${c.subscription.plan}` : '—',
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
                <OutlineButton
                  variant="outline"
                  size="sm"
                  disabled={impersonatingId === c.id}
                  onClick={() => handleImpersonate(c.id)}
                >
                  {impersonatingId === c.id ? 'Opening…' : 'Impersonate'}
                </OutlineButton>
              </div>
            ),
          },
        ]}
        rows={companies as Company[]}
        onRowClick={(c) => navigate(`/platform/companies/${c.id}`)}
        emptyState={<EmptyState title="No companies" description="Create your first client organization." />}
      />

      <Modal open={showForm} onClose={() => setShowForm(false)} title="Create company">
        <form onSubmit={handleCreate} className="space-y-4">
          <Input label="Company name" value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} required />
          <Input
            label="Admin email"
            type="email"
            value={form.admin_email}
            onChange={(e) => setForm({ ...form, admin_email: e.target.value })}
            required
          />
          <Input
            label="Admin name"
            value={form.admin_name}
            onChange={(e) => setForm({ ...form, admin_name: e.target.value })}
            required
          />
          <div className="flex justify-end gap-2">
            <Button type="button" variant="secondary" onClick={() => setShowForm(false)}>
              Cancel
            </Button>
            <Button type="submit">Create</Button>
          </div>
        </form>
      </Modal>
    </div>
  );
}
