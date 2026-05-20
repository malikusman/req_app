import { useState, type FormEvent } from 'react';
import { AuthLayout, type AuthPortal } from '../components/layout/AuthLayout';
import { Input } from '../components/ui/Input';
import { Button } from '../components/ui/Button';

type Props = {
  portal: AuthPortal;
  portalName: string;
  tagline: string;
  defaultEmail: string;
  footer?: React.ReactNode;
  onSubmit: (email: string, password: string) => Promise<void>;
};

export function LoginForm({ portal, portalName, tagline, defaultEmail, footer, onSubmit }: Props) {
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
    <AuthLayout portal={portal} portalName={portalName} tagline={tagline}>
      <form onSubmit={handleSubmit} className="space-y-4">
        {error && (
          <div className="rounded-button border border-status-error/30 bg-status-errorBg px-3 py-2 text-sm text-status-error">
            {error}
          </div>
        )}
        <Input
          label="Email"
          id="email"
          type="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          required
        />
        <div>
          <Input
            label="Password"
            id="password"
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
          />
          <a href="#" className="mt-1.5 inline-block text-sm text-text-secondary hover:text-accent">
            Forgot password?
          </a>
        </div>
        <Button type="submit" className="w-full" loading={loading}>
          Sign in
        </Button>
        {footer && <p className="text-center text-sm text-text-secondary">{footer}</p>}
      </form>
    </AuthLayout>
  );
}
