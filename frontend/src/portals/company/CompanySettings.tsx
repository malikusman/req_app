import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { ClipboardList } from 'lucide-react';
import { api } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { PageHeader, Card, Input, Select, Button, StatCard, Skeleton } from '../../components/ui';
import { SETTINGS_SECONDARY_LINKS } from './nav';

export function CompanySettings() {
  const token = useCompanyToken();
  const [displayName, setDisplayName] = useState('');
  const [locale, setLocale] = useState('en');
  const [security, setSecurity] = useState<{
    active_access_codes: number;
    security_snapshot: Record<string, unknown>;
  } | null>(null);
  const [loadError, setLoadError] = useState('');

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
    try {
      await api.updateCompanySettings(token, {
        display_name: displayName,
        locale,
      });
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

      <Card title="Company profile">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div className="min-w-0">
            <p className="m-0 text-sm text-muted-foreground">
              Industry, systems, website, goals, and other business details are edited in the guided profile.
            </p>
          </div>
          <Link to="/company/onboarding">
            <Button variant="secondary" icon={<ClipboardList className="h-4 w-4" />}>
              Open profile
            </Button>
          </Link>
        </div>
      </Card>

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
          <Button type="submit">Save</Button>
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
              Access codes unlock WhatsApp or web discovery for invited employees. View and rotate codes on the
              Employees page.
            </p>
            <StatCard label="Active access codes" value={security.active_access_codes} />
            <p className="text-sm text-text-secondary">
              Unrecognized verification attempts (7d):{' '}
              {String(security.security_snapshot?.unrecognized_verification_attempts_7d ?? 0)}
            </p>
            <Link to="/company/employees">
              <Button variant="secondary">Manage access codes</Button>
            </Link>
          </div>
        )}
      </Card>
    </div>
  );
}
