import { useEffect, useState, type FormEvent } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { AuthLayout, type AuthPortal } from '../components/layout/AuthLayout';
import { ShineBorder } from '../components/motion';
import { PasswordInput } from '../components/ui/PasswordInput';
import { Button } from '../components/ui/Button';
import { api } from '../lib/api';

export function SetPasswordPage() {
  const [params] = useSearchParams();
  const token = params.get('token') || '';
  const portalHint = (params.get('portal') as AuthPortal) || 'company';
  const [portal, setPortal] = useState<AuthPortal>(portalHint);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirmation, setConfirmation] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const [verifying, setVerifying] = useState(true);
  const [done, setDone] = useState(false);

  useEffect(() => {
    if (!token) {
      setError('Missing reset token');
      setVerifying(false);
      return;
    }
    api
      .verifyPasswordReset(token)
      .then((data) => {
        setPortal((data.portal as AuthPortal) || portalHint);
        setEmail(data.email);
      })
      .catch((err) => setError(err instanceof Error ? err.message : 'Invalid link'))
      .finally(() => setVerifying(false));
  }, [token, portalHint]);

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);
    try {
      await api.confirmPasswordReset(token, password, confirmation);
      setDone(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not set password');
    } finally {
      setLoading(false);
    }
  };

  return (
    <AuthLayout portal={portal} portalName="Worktruth" tagline="Choose a password to finish setting up your account.">
      <div className="mb-6">
        <h1 className="font-display text-page-title text-text-primary m-0">Set password</h1>
        {email ? <p className="mt-1 text-sm text-text-secondary">{email}</p> : null}
      </div>

      <ShineBorder className="shadow-card">
        {verifying ? (
          <p className="p-6 text-sm text-text-secondary">Checking link…</p>
        ) : done ? (
          <div className="space-y-3 p-6">
            <p className="m-0 font-display text-lg text-text-primary">Password saved</p>
            <Link to={`/${portal}/login`} className="text-sm text-accent">
              Continue to sign in
            </Link>
          </div>
        ) : (
          <form onSubmit={handleSubmit} className="space-y-4 p-6">
            {error ? (
              <div className="rounded-button border border-status-error/30 bg-status-errorBg px-3 py-2 text-sm text-status-error">
                {error}
              </div>
            ) : null}
            <PasswordInput
              label="New password"
              id="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              autoComplete="new-password"
              required
              minLength={8}
            />
            <PasswordInput
              label="Confirm password"
              id="password_confirmation"
              value={confirmation}
              onChange={(e) => setConfirmation(e.target.value)}
              autoComplete="new-password"
              required
              minLength={8}
            />
            <Button type="submit" className="w-full" loading={loading} disabled={!!error && !password}>
              Save password
            </Button>
          </form>
        )}
      </ShineBorder>
    </AuthLayout>
  );
}
