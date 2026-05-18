import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api, type Company } from '../../lib/api';
import { useAuth, usePlatformToken, startImpersonation } from '../../lib/auth';
import { PlatformCompanyReviewers } from './PlatformCompanyReviewers';

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
  const [reviewerCompany, setReviewerCompany] = useState<{ id: number; name: string } | null>(null);

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

  if (loading) return <p>Loading…</p>;

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1.5rem' }}>
        <h1 style={{ margin: 0 }}>Companies</h1>
        <button type="button" className="btn btn-primary" onClick={() => setShowForm(!showForm)}>
          {showForm ? 'Cancel' : 'New company'}
        </button>
      </div>

      {showForm && (
        <div className="card" style={{ marginBottom: '1.5rem' }}>
          <h3 style={{ marginTop: 0 }}>Create company</h3>
          {error && <div className="error">{error}</div>}
          <form onSubmit={handleCreate}>
            <div className="form-group">
              <label>Company name</label>
              <input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} required />
            </div>
            <div className="form-group">
              <label>Admin email</label>
              <input
                type="email"
                value={form.admin_email}
                onChange={(e) => setForm({ ...form, admin_email: e.target.value })}
                required
              />
            </div>
            <div className="form-group">
              <label>Admin name</label>
              <input value={form.admin_name} onChange={(e) => setForm({ ...form, admin_name: e.target.value })} required />
            </div>
            <button type="submit" className="btn btn-primary">
              Create
            </button>
          </form>
        </div>
      )}

      <div className="card">
        <table>
          <thead>
            <tr>
              <th>Name</th>
              <th>Readiness</th>
              <th>Subscription</th>
              <th>Onboarding</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {companies.map((c) => (
              <tr key={c.id}>
                <td>
                  <strong>{c.display_name || c.name}</strong>
                  <br />
                  <small style={{ color: '#94a3b8' }}>{c.slug}</small>
                </td>
                <td>{Math.round(c.report_readiness_score)}%</td>
                <td>
                  {c.subscription?.status} · {c.subscription?.plan}
                </td>
                <td>{c.portal_onboarding_completed_at ? 'Complete' : 'Pending'}</td>
                <td style={{ display: 'flex', gap: '0.5rem', flexWrap: 'wrap' }}>
                  <button
                    type="button"
                    className="btn btn-secondary btn-sm"
                    onClick={() =>
                      setReviewerCompany({ id: c.id, name: c.display_name || c.name })
                    }
                  >
                    Reviewers
                  </button>
                  <button
                    type="button"
                    className="btn btn-secondary btn-sm"
                    disabled={impersonatingId === c.id}
                    onClick={() => handleImpersonate(c.id)}
                  >
                    {impersonatingId === c.id ? 'Opening…' : 'Impersonate'}
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {companies.length === 0 && <p style={{ color: '#64748b' }}>No companies yet.</p>}
      </div>
      {reviewerCompany && (
        <PlatformCompanyReviewers
          companyId={reviewerCompany.id}
          companyName={reviewerCompany.name}
          onClose={() => setReviewerCompany(null)}
        />
      )}
    </div>
  );
}
