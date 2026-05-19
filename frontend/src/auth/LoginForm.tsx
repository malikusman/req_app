import { useState, type FormEvent } from 'react';
import { AuthLayout } from '../components/layout/AuthLayout';
import { Input } from '../components/ui/Input';
import { Button } from '../components/ui/Button';

type Props = {
  portalName: string;
  tagline: string;
  defaultEmail: string;
  footer?: React.ReactNode;
  onSubmit: (email: string, password: string) => Promise<void>;
};

export function LoginForm({ portalName, tagline, defaultEmail, footer, onSubmit }: Props) {
  const [email, setEmail] = useState(defaultEmail);
  const [password, setPassword] = useState('password123');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);
    try {
      await onSubmit(email, password);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Login failed');
    } finally {
      setLoading(false);
    }
  };

  return (
    <AuthLayout portalName={portalName} tagline={tagline}>
      <form onSubmit={handleSubmit} className="space-y-4">
        {error && (
          <div className="rounded-button border border-status-error/30 bg-status-errorBg px-3 py-2 text-sm text-status-error">
            {error}
          </div>
        )}
        <Input label="Email" id="email" type="email" value={email} onChange={(e) => setEmail(e.target.value)} required />
        <Input label="Password" id="password" type="password" value={password} onChange={(e) => setPassword(e.target.value)} required />
        <Button type="submit" className="w-full" loading={loading}>
          Sign in
        </Button>
        {footer && <p className="text-center text-sm text-text-secondary">{footer}</p>}
      </form>
    </AuthLayout>
  );
}
