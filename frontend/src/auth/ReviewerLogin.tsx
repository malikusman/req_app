import { useState, type FormEvent } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { api } from '../lib/api';
import { useAuth } from '../lib/auth';

export function ReviewerLogin() {
  const { setSession } = useAuth();
  const navigate = useNavigate();
  const [email, setEmail] = useState('reviewer@reqapp.local');
  const [password, setPassword] = useState('password123');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);
    try {
      const res = await api.reviewerLogin(email, password);
      setSession({ portal: 'reviewer', token: res.token, user: res.user });
      navigate('/reviewer/dashboard');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Login failed');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="login-page" style={{ background: 'linear-gradient(135deg, #4c1d95 0%, #7c3aed 100%)' }}>
      <div className="login-card">
        <h1>Reviewer Portal</h1>
        <p className="subtitle">Expert report review access</p>
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
        <p style={{ marginTop: '1rem', textAlign: 'center' }}>
          <Link to="/">Back to home</Link>
        </p>
      </div>
    </div>
  );
}
