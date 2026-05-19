import { useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { api, type Company } from '../../lib/api';
import { useAuth, usePlatformToken, startImpersonation } from '../../lib/auth';
import {
  PageHeader,
  Button,
  DataTable,
  Badge,
  Input,
  EmptyState,
  Modal,
} from '../../components/ui';

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
    api
      .platformCompanies(token)
      .then((d) => setCompanies(d.companies))
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
      startImpersonation(setSession, session, {
        token: res.token,
        user: { ...res.user, onboarding_completed_at: null },
        company: {
          id: res.company.id,
          name: res.company.display_name || res.company.name,
          portal_onboarding_completed_at: res.company.portal_onboarding_completed_at,
        },
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

      {error && <p className="text-sm text-status-error">{error}</p>}

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
                  className="font-medium text-accent hover:underline"
                  onClick={(e) => e.stopPropagation()}
                >
                  {c.display_name || c.name}
                </Link>
                <p className="m-0 text-xs text-text-secondary">{c.slug}</p>
              </div>
            ),
          },
          {
            key: 'readiness',
            header: 'Readiness',
            render: (c) => `${Math.round(c.report_readiness_score)}%`,
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
              <Badge variant={c.portal_onboarding_completed_at ? 'success' : 'warning'}>
                {c.portal_onboarding_completed_at ? 'Complete' : 'Pending'}
              </Badge>
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
                  disabled={impersonatingId === c.id}
                  onClick={() => handleImpersonate(c.id)}
                >
                  {impersonatingId === c.id ? 'Opening…' : 'Impersonate'}
                </Button>
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
