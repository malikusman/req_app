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

  const load = () => {
    if (!token) return;
    setLoadError('');
    api
      .companySettingsOrganization(token)
      .then((d) => {
        setDisplayName(d.company.display_name || '');
        setLocale(d.company.locale);
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

  return (
    <div className="space-y-6">
      <PageHeader title="Settings" description="Account preferences, security, and secondary tools." />

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
            label="Locale (reports)"
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

      <Card title="More tools">
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
              Employees join only after an admin invite. WhatsApp uses the invited phone number; browser
              discovery uses the personal link from email.
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
