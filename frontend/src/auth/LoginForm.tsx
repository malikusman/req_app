import { useState, type FormEvent } from 'react';
import { Link } from 'react-router-dom';
import { AnimatePresence, motion, useReducedMotion } from 'motion/react';
import { AuthLayout, type AuthPortal } from '../components/layout/AuthLayout';
import { ShineBorder } from '../components/motion';
import { Input } from '../components/ui/Input';
import { Button } from '../components/ui/Button';
import { shake, transition } from '../lib/motion';

type Props = {
  portal: AuthPortal;
  portalName: string;
  tagline: string;
  defaultEmail: string;
  footer?: React.ReactNode;
  forgotPasswordTo?: string;
  onSubmit: (email: string, password: string) => Promise<void>;
};

export function LoginForm({
  portal,
  portalName,
  tagline,
  defaultEmail,
  footer,
  forgotPasswordTo,
  onSubmit,
}: Props) {
  const [email, setEmail] = useState(defaultEmail);
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const reduced = useReducedMotion();

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
      <div className="mb-6">
        <h1 className="font-display text-page-title text-text-primary m-0">Sign in</h1>
        <p className="mt-1 text-sm text-text-secondary">Enter your credentials to continue.</p>
      </div>

      <ShineBorder className="shadow-card">
        <motion.form
          onSubmit={handleSubmit}
          className="space-y-4 p-6"
          initial="idle"
          animate={error && !reduced ? 'shake' : 'idle'}
          variants={shake}
        >
          <AnimatePresence mode="wait">
            {error && (
              <motion.div
                key="error"
                initial={{ opacity: 0, height: 0 }}
                animate={{ opacity: 1, height: 'auto' }}
                exit={{ opacity: 0, height: 0 }}
                transition={transition.fast}
                className="overflow-hidden rounded-button border border-status-error/30 bg-status-errorBg px-3 py-2 text-sm text-status-error"
                role="alert"
              >
                {error}
              </motion.div>
            )}
          </AnimatePresence>
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
            {forgotPasswordTo ? (
              <Link
                to={forgotPasswordTo}
                className="mt-1.5 inline-block text-sm text-text-secondary hover:text-accent"
              >
                Forgot password?
              </Link>
            ) : null}
          </div>
          <Button type="submit" className="w-full" loading={loading}>
            Sign in
          </Button>
          {footer && <p className="text-center text-sm text-text-secondary">{footer}</p>}
        </motion.form>
      </ShineBorder>
    </AuthLayout>
  );
}
