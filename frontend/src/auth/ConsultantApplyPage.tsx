import { useState, type FormEvent } from 'react';
import { Link } from 'react-router-dom';
import { AuthLayout } from '../components/layout/AuthLayout';
import { ShineBorder } from '../components/motion';
import { Input } from '../components/ui/Input';
import { Button } from '../components/ui/Button';
import { api } from '../lib/api';

export function ConsultantApplyPage() {
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [headline, setHeadline] = useState('');
  const [expertise, setExpertise] = useState('');
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
      await api.publicConsultantApplication({
        name,
        email,
        headline: headline || undefined,
        expertise_summary: expertise || undefined,
        notes: notes || undefined,
        website: website || undefined,
      });
      setDone(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Application failed');
    } finally {
      setLoading(false);
    }
  };

  return (
    <AuthLayout
      portal="consultant"
      portalName="Worktruth — Consultant"
      tagline="Apply to review discovery reports. Access is granted after platform approval."
    >
      <div className="mb-6">
        <h1 className="font-display text-page-title text-text-primary m-0">Become a consultant</h1>
        <p className="mt-1 text-sm text-text-secondary">
          Already approved? <Link to="/consultant/login">Sign in</Link>
        </p>
      </div>

      <ShineBorder className="shadow-card">
        {done ? (
          <div className="space-y-3 p-6">
            <p className="m-0 font-display text-lg text-text-primary">Application received</p>
            <p className="m-0 text-sm text-text-secondary">
              We&apos;ll email you when a platform admin reviews your application.
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
            <Input label="Full name" id="name" value={name} onChange={(e) => setName(e.target.value)} required />
            <Input
              label="Email"
              id="email"
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
            />
            <Input
              label="Headline (optional)"
              id="headline"
              value={headline}
              onChange={(e) => setHeadline(e.target.value)}
            />
            <Input
              label="Expertise summary (optional)"
              id="expertise"
              value={expertise}
              onChange={(e) => setExpertise(e.target.value)}
            />
            <Input label="Notes (optional)" id="notes" value={notes} onChange={(e) => setNotes(e.target.value)} />
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
              Submit application
            </Button>
          </form>
        )}
      </ShineBorder>
    </AuthLayout>
  );
}
