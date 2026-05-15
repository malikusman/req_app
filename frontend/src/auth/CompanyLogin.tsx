import { useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { api } from '../lib/api';
import { useAuth } from '../lib/auth';

export function CompanyLogin() {
  const [email, setEmail] = useState('admin@acme.local');
  const [password, setPassword] = useState('password123');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const { setSession } = useAuth();
  const navigate = useNavigate();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);
    try {
      const data = await api.companyLogin(email, password);
      setSession({
        portal: 'company',
        token: data.token,
        user: data.user,
        company: {
          id: data.company.id,
          name: data.company.display_name || data.company.name,
          portal_onboarding_completed_at: data.company.portal_onboarding_completed_at,
        },
      });
      if (!data.company.portal_onboarding_completed_at) {
        navigate('/company/onboarding');
      } else {
        navigate('/company/dashboard');
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Login failed');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="login-page" style={{ background: 'linear-gradient(135deg, #1e3a5f 0%, #2563eb 100%)' }}>
      <div className="login-card">
        <h1>Company Portal</h1>
        <p className="subtitle">Sign in to run workflow discovery</p>
        {error && <div className="error">{error}</div>}
        <form onSubmit={handleSubmit}>
          <div className="form-group">
            <label htmlFor="email">Email</label>
            <input id="email" type="email" value={email} onChange={(e) => setEmail(e.target.value)} required />
          </div>
          <div className="form-group">
            <label htmlFor="password">Password</label>
            <input id="password" type="password" value={password} onChange={(e) => setPassword(e.target.value)} required />
          </div>
          <button type="submit" className="btn btn-primary" style={{ width: '100%' }} disabled={loading}>
            {loading ? 'Signing in…' : 'Sign in'}
          </button>
        </form>
        <p style={{ marginTop: '1.5rem', fontSize: '0.85rem', color: '#64748b', textAlign: 'center' }}>
          Platform team? <Link to="/platform/login">Platform login</Link>
        </p>
      </div>
    </div>
  );
}
