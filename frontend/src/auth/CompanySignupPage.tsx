import { useState, type FormEvent } from 'react';
import { Link } from 'react-router-dom';
import { AuthLayout } from '../components/layout/AuthLayout';
import { ShineBorder } from '../components/motion';
import { Input } from '../components/ui/Input';
import { Button } from '../components/ui/Button';
import { api } from '../lib/api';

export function CompanySignupPage() {
  const [companyName, setCompanyName] = useState('');
  const [adminName, setAdminName] = useState('');
  const [adminEmail, setAdminEmail] = useState('');
  const [roleTitle, setRoleTitle] = useState('');
  const [notes, setNotes] = useState('');
  const [website, setWebsite] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const [done, setDone] = useState(false);

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);
    try {
      await api.publicCompanyRegistration({
        company_name: companyName,
        admin_name: adminName,
        admin_email: adminEmail,
        role_title: roleTitle || undefined,
        notes: notes || undefined,
        website: website || undefined,
      });
      setDone(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Signup failed');
    } finally {
      setLoading(false);
    }
  };

  return (
    <AuthLayout
      portal="company"
      portalName="Worktruth — Company"
      tagline="Request a company account. A platform admin will approve access before you can sign in."
    >
      <div className="mb-6">
        <h1 className="font-display text-page-title text-text-primary m-0">Create a company account</h1>
        <p className="mt-1 text-sm text-text-secondary">
          Already approved? <Link to="/company/login">Sign in</Link>
        </p>
      </div>

      <ShineBorder className="shadow-card">
        {done ? (
          <div className="space-y-3 p-6">
            <p className="m-0 font-display text-lg text-text-primary">Request received</p>
            <p className="m-0 text-sm text-text-secondary">
              Check your email for confirmation. We&apos;ll send a set-password link once a platform admin
              approves your account.
            </p>
            <Link to="/" className="text-sm text-accent">
              Back to home
            </Link>
          </div>
        ) : (
          <form onSubmit={handleSubmit} className="space-y-4 p-6">
            {error ? (
              <div className="rounded-button border border-status-error/30 bg-status-errorBg px-3 py-2 text-sm text-status-error">
                {error}
              </div>
            ) : null}
            <Input
              label="Company name"
              id="company_name"
              value={companyName}
              onChange={(e) => setCompanyName(e.target.value)}
              required
            />
            <Input
              label="Your name"
              id="admin_name"
              value={adminName}
              onChange={(e) => setAdminName(e.target.value)}
              required
            />
            <Input
              label="Work email"
              id="admin_email"
              type="email"
              value={adminEmail}
              onChange={(e) => setAdminEmail(e.target.value)}
              required
            />
            <Input
              label="Role (optional)"
              id="role_title"
              value={roleTitle}
              onChange={(e) => setRoleTitle(e.target.value)}
            />
            <Input
              label="Notes (optional)"
              id="notes"
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
            />
            {/* Honeypot */}
            <input
              type="text"
              name="website"
              value={website}
              onChange={(e) => setWebsite(e.target.value)}
              className="hidden"
              tabIndex={-1}
              autoComplete="off"
              aria-hidden
            />
            <Button type="submit" className="w-full" loading={loading}>
              Request access
            </Button>
          </form>
        )}
      </ShineBorder>
    </AuthLayout>
  );
}
