import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api, type Employee } from '../../lib/api';
import { useCompanyToken, useAuth } from '../../lib/auth';
import { PageHeader, Card, Input, Select, Button, ProgressBar, Textarea } from '../../components/ui';

export function CompanyOnboarding() {
  const token = useCompanyToken();
  const { session, setSession } = useAuth();
  const navigate = useNavigate();
  const [step, setStep] = useState(1);
  const [displayName, setDisplayName] = useState('');
  const [locale, setLocale] = useState('en');
  const [engagementMode, setEngagementMode] = useState('hybrid');
  const [phone, setPhone] = useState('');
  const [name, setName] = useState('');
  const [department, setDepartment] = useState('');
  const [invited, setInvited] = useState<(Employee & { access_code?: string })[]>([]);
  const [lastCode, setLastCode] = useState('');
  const [bulkPhones, setBulkPhones] = useState('');
  const [bulkInviting, setBulkInviting] = useState(false);
  const [skippedInvites, setSkippedInvites] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    if (!token) return;
    api.companyOnboarding(token).then((d) => {
      setStep(d.step);
      setDisplayName(d.company.display_name || '');
      setLocale(d.company.locale || 'en');
      if (d.company.engagement_mode) setEngagementMode(d.company.engagement_mode);
    });
  }, [token]);

  const saveProfile = async () => {
    if (!token) return;
    setError('');
    try {
      const res = await api.updateOnboardingProfile(token, displayName, locale, engagementMode);
      setStep(res.step);
      if (res.engagement_mode) setEngagementMode(res.engagement_mode);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save');
    }
  };

  const inviteEmployee = async () => {
    if (!token || !phone) return;
    setError('');
    try {
      const res = await api.inviteEmployee(token, phone, name || undefined, department || undefined);
      setLastCode(res.access_code);
      setInvited((prev) => [...prev, { ...res.employee, access_code: res.access_code }]);
      setPhone('');
      setName('');
      setDepartment('');
      setSkippedInvites(false);
      setStep(3);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to invite');
    }
  };

  const bulkInvite = async () => {
    if (!token) return;
    const phones = bulkPhones
      .split(/[\n,]+/)
      .map((p) => p.trim())
      .filter(Boolean);
    if (phones.length === 0) return;

    setError('');
    setBulkInviting(true);
    try {
      const res = await api.bulkInviteEmployees(
        token,
        phones.map((phone_e164) => ({ phone_e164, department: department || undefined }))
      );
      setInvited((prev) => [
        ...prev,
        ...res.employees.map((e) => ({ ...e, access_code: e.access_code })),
      ]);
      setBulkPhones('');
      setSkippedInvites(false);
      setStep(3);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Bulk invite failed');
    } finally {
      setBulkInviting(false);
    }
  };

  const skipInvites = () => {
    setSkippedInvites(true);
    setStep(3);
  };

  const finish = async () => {
    if (!token) return;
    await api.completeOnboarding(token);
    if (session?.portal === 'company') {
      setSession({
        ...session,
        company: { ...session.company, portal_onboarding_completed_at: new Date().toISOString() },
      });
    }
    navigate(skippedInvites || invited.length === 0 ? '/company/documents' : '/company/dashboard');
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="Welcome — let's get started"
        description="Start with internal documents, invite employees now, or add people later."
      />

      <div>
        <p className="mb-2 text-sm text-text-secondary">Step {step} of 3</p>
        <ProgressBar value={(step / 3) * 100} />
      </div>

      {error && <p className="text-sm text-status-error">{error}</p>}

      {step === 1 && (
        <Card title="Step 1 — Company profile">
          <div className="max-w-md space-y-4">
            <Input
              label="Display name"
              value={displayName}
              onChange={(e) => setDisplayName(e.target.value)}
              placeholder="Acme Corporation"
            />
            <Select
              label="Default language (for reports)"
              value={locale}
              onChange={(e) => setLocale(e.target.value)}
              options={[
                { value: 'en', label: 'English' },
                { value: 'es', label: 'Spanish' },
                { value: 'fr', label: 'French' },
                { value: 'de', label: 'German' },
              ]}
            />
            <Select
              label="How will you start discovery?"
              value={engagementMode}
              onChange={(e) => setEngagementMode(e.target.value)}
              options={[
                {
                  value: 'hybrid',
                  label: 'Docs now → people later (baseline report, then interviews strengthen it)',
                },
                {
                  value: 'documents',
                  label: 'Documents only (baseline PDF without invites)',
                },
                {
                  value: 'interview',
                  label: 'Employees first (WhatsApp / web interviews, docs optional)',
                },
              ]}
            />
            <p className="text-xs text-text-secondary">
              Next: optional invites, then a short checklist — documents path lands you on Documents to upload.
            </p>
            <Button onClick={saveProfile}>Continue</Button>
          </div>
        </Card>
      )}

      {step === 2 && (
        <Card title="Step 2 — Invite employees (optional)">
          <p className="text-sm text-text-secondary">
            You can invite people now, or skip and upload ISO / procedure / finance documents first.
            Interviews later will strengthen the same intelligence baseline — not replace it.
          </p>
          <div className="mt-4 max-w-md space-y-4">
            <Input
              label="Mobile number (with country code)"
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
              placeholder="+1 415 555 1234"
            />
            <Input label="Name (optional)" value={name} onChange={(e) => setName(e.target.value)} />
            <Input
              label="Department (optional)"
              value={department}
              onChange={(e) => setDepartment(e.target.value)}
              placeholder="finance"
            />
            <Button onClick={inviteEmployee} disabled={!phone}>
              Invite & generate access code
            </Button>

            <div className="border-t border-border pt-4">
              <Textarea
                label="Bulk invite (one phone per line)"
                value={bulkPhones}
                onChange={(e) => setBulkPhones(e.target.value)}
                placeholder={"+14155551001\n+14155551002\n+14155551003"}
                rows={4}
              />
              <Button
                variant="secondary"
                className="mt-2"
                loading={bulkInviting}
                disabled={!bulkPhones.trim()}
                onClick={bulkInvite}
              >
                Bulk invite
              </Button>
            </div>

            {lastCode && (
              <div className="rounded-button border border-border bg-surface-muted p-4">
                <p className="m-0 text-sm text-text-secondary">Latest access code (share privately):</p>
                <p className="mt-2 font-mono text-lg font-semibold">{lastCode}</p>
              </div>
            )}
            <div className="flex flex-wrap gap-2 pt-2">
              {invited.length > 0 && (
                <Button variant="secondary" onClick={() => setStep(3)}>
                  Continue ({invited.length} invited)
                </Button>
              )}
              <Button variant="ghost" onClick={skipInvites}>
                Skip for now — start with documents
              </Button>
            </div>
          </div>
        </Card>
      )}

      {step >= 3 && (
        <Card title={skippedInvites || invited.length === 0 ? 'Step 3 — Start with documents' : 'Step 3 — Share instructions'}>
          {skippedInvites || invited.length === 0 ? (
            <ul className="list-inside list-disc space-y-2 text-sm text-text-secondary">
              <li>Upload ISO certificates, SOPs, and finance files from Documents</li>
              <li>Tag documents with a department when possible for better coverage</li>
              <li>Baseline intelligence builds from your corpus; invite employees later to strengthen it</li>
            </ul>
          ) : (
            <ul className="list-inside list-disc space-y-2 text-sm text-text-secondary">
              <li>Share the bot number with each invited employee</li>
              <li>Send each person their unique access code via email or Slack</li>
              <li>Never post access codes in public channels</li>
            </ul>
          )}
          {invited.length > 0 && (
            <ul className="mt-4 space-y-2 text-sm">
              {invited.map((e) => (
                <li key={e.id} className="rounded-button border border-border px-3 py-2">
                  {e.display_name || e.phone_e164} — <code className="text-accent">{e.access_code}</code>
                </li>
              ))}
            </ul>
          )}
          <Button className="mt-4" onClick={finish}>
            {skippedInvites || invited.length === 0 ? 'Go to documents' : 'Go to dashboard'}
          </Button>
        </Card>
      )}
    </div>
  );
}
