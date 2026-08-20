import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { api } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { PageHeader, Card, Input, Select, Button, Skeleton } from '../../components/ui';
import { SETTINGS_SECONDARY_LINKS } from './nav';

export function CompanySettings() {
  const token = useCompanyToken();
  const [displayName, setDisplayName] = useState('');
  const [locale, setLocale] = useState('en');
  const [security, setSecurity] = useState<{
    security_snapshot: Record<string, unknown>;
  } | null>(null);
  const [loadError, setLoadError] = useState('');
  const [saved, setSaved] = useState(false);
  const [reviewerCanContact, setReviewerCanContact] = useState(true);
  const [savingReviewer, setSavingReviewer] = useState(false);

  const load = () => {
    if (!token) return;
    setLoadError('');
    api
      .companySettingsOrganization(token)
      .then((d) => {
        setDisplayName(d.company.display_name || '');
        setLocale(d.company.locale);
        setReviewerCanContact(d.settings?.reviewer_can_contact_employees !== false);
      })
      .catch(() => setLoadError('Could not load settings.'));
    api
      .companySettingsSecurity(token)
      .then(setSecurity)
      .catch(() => setLoadError('Could not load settings.'));
  };

  useEffect(() => {
    load();
  }, [token]);

  const saveOrg = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!token) return;
    setSaved(false);
    try {
      await api.updateCompanySettings(token, {
        display_name: displayName,
        locale,
      });
      setSaved(true);
    } catch {
      setLoadError('Could not update organization settings.');
    }
  };

  const toggleReviewerContact = async () => {
    if (!token || savingReviewer) return;
    const next = !reviewerCanContact;
    setReviewerCanContact(next); // optimistic
    setSavingReviewer(true);
    try {
      await api.updateCompanySettings(token, { reviewer_can_contact_employees: next });
    } catch {
      setReviewerCanContact(!next); // revert
      setLoadError('Could not update reviewer access.');
    } finally {
      setSavingReviewer(false);
    }
  };

  return (
    <div className="space-y-6">
      <PageHeader title="Settings" description="Your organization details, security, and other tools." />

      {loadError && (
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-button border border-status-error/30 bg-status-errorBg px-4 py-3 text-sm text-status-error">
          <span>{loadError}</span>
          <Button size="sm" variant="secondary" onClick={load}>
            Retry
          </Button>
        </div>
      )}

      <Card title="Organization">
        <form onSubmit={saveOrg} className="max-w-md space-y-4">
          <Input label="Display name" value={displayName} onChange={(e) => setDisplayName(e.target.value)} />
          <Select
            label="Report language"
            value={locale}
            onChange={(e) => setLocale(e.target.value)}
            options={[
              { value: 'en', label: 'English' },
              { value: 'es', label: 'Spanish' },
              { value: 'fr', label: 'French' },
              { value: 'de', label: 'German' },
            ]}
          />
          <div className="flex flex-wrap items-center gap-3">
            <Button type="submit">Save</Button>
            {saved ? <span className="text-sm text-status-success">Saved</span> : null}
          </div>
        </form>
      </Card>

      <Card title="Reviewer access">
        <div className="flex items-start justify-between gap-4">
          <div className="min-w-0">
            <p className="m-0 font-medium text-foreground">Let your reviewer message employees</p>
            <p className="m-0 mt-1 text-sm text-muted-foreground">
              When on, your assigned expert reviewer can send a WhatsApp follow-up directly to an employee to
              clarify their answers while reviewing your report. Turn off to require every reviewer question to
              go through you first.
            </p>
          </div>
          <button
            type="button"
            role="switch"
            aria-checked={reviewerCanContact}
            aria-label="Let your reviewer message employees"
            disabled={savingReviewer}
            onClick={toggleReviewerContact}
            className={`relative inline-flex h-6 w-11 shrink-0 items-center rounded-full transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2 disabled:opacity-60 ${
              reviewerCanContact ? 'bg-primary' : 'bg-muted'
            }`}
          >
            <span
              className={`inline-block h-5 w-5 transform rounded-full bg-card shadow transition-transform ${
                reviewerCanContact ? 'translate-x-5' : 'translate-x-0.5'
              }`}
            />
          </button>
        </div>
      </Card>

      <Card title="Other tools">
        <div className="grid gap-3 sm:grid-cols-2">
          {SETTINGS_SECONDARY_LINKS.map((item) => {
            const Icon = item.icon;
            return (
              <Link
                key={item.to}
                to={item.to}
                className="flex items-start gap-3 rounded-lg border border-border p-3 transition-colors hover:border-primary/40 hover:bg-muted/40"
              >
                <Icon className="mt-0.5 h-5 w-5 shrink-0 text-primary" />
                <div className="min-w-0">
                  <p className="m-0 font-medium text-foreground">{item.label}</p>
                  <p className="m-0 text-sm text-muted-foreground">{item.description}</p>
                </div>
              </Link>
            );
          })}
        </div>
      </Card>

      <Card title="Security">
        {!security ? (
          <div className="space-y-4">
            <Skeleton variant="text" />
            <Skeleton variant="text" />
          </div>
        ) : (
          <div className="space-y-4">
            <p className="m-0 text-sm text-text-secondary">
              Your team can only join by invitation. On WhatsApp we use the phone number you invited; in the
              browser, each person uses their own private link from email.
            </p>
            <Link to="/company/employees">
              <Button variant="secondary">Manage employees</Button>
            </Link>
          </div>
        )}
      </Card>
    </div>
  );
}
