import { useState, type FormEvent } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { AuthLayout, type AuthPortal } from '../components/layout/AuthLayout';
import { ShineBorder } from '../components/motion';
import { Input } from '../components/ui/Input';
import { Button } from '../components/ui/Button';
import { api } from '../lib/api';

const PORTALS: AuthPortal[] = ['company', 'reviewer', 'platform'];

export function ForgotPasswordPage() {
  const [params] = useSearchParams();
  const initial = PORTALS.includes(params.get('portal') as AuthPortal)
    ? (params.get('portal') as AuthPortal)
    : 'company';
  const [portal, setPortal] = useState<AuthPortal>(initial);
  const [email, setEmail] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const [done, setDone] = useState(false);

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);
    try {
      await api.requestPasswordReset(portal, email);
      setDone(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Request failed');
    } finally {
      setLoading(false);
    }
  };

  return (
    <AuthLayout portal={portal} portalName="Worktruth" tagline="Reset your password with a secure email link.">
      <div className="mb-6">
        <h1 className="font-display text-page-title text-text-primary m-0">Forgot password</h1>
        <p className="mt-1 text-sm text-text-secondary">
          <Link to={`/${portal}/login`}>Back to sign in</Link>
        </p>
      </div>

      <ShineBorder className="shadow-card">
        {done ? (
          <div className="space-y-3 p-6">
            <p className="m-0 font-display text-lg text-text-primary">Check your email</p>
            <p className="m-0 text-sm text-text-secondary">
              If an account exists for that email, we sent a link to reset your password.
            </p>
          </div>
        ) : (
          <form onSubmit={handleSubmit} className="space-y-4 p-6">
            {error ? (
              <div className="rounded-button border border-status-error/30 bg-status-errorBg px-3 py-2 text-sm text-status-error">
                {error}
              </div>
            ) : null}
            <label className="block text-sm text-text-secondary">
              Portal
              <select
                className="mt-1 w-full rounded-button border border-border bg-surface px-3 py-2 text-text-primary"
                value={portal}
                onChange={(e) => setPortal(e.target.value as AuthPortal)}
              >
                <option value="company">Company</option>
                <option value="reviewer">Reviewer</option>
                <option value="platform">Platform</option>
              </select>
            </label>
            <Input
              label="Email"
              id="email"
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
            />
            <Button type="submit" className="w-full" loading={loading}>
              Send reset link
            </Button>
          </form>
        )}
      </ShineBorder>
    </AuthLayout>
  );
}
