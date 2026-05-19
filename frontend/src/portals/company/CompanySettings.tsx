import { useEffect, useState } from 'react';
import { api } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { PageHeader, Card, Input, Select, Button, StatCard } from '../../components/ui';

export function CompanySettings() {
  const token = useCompanyToken();
  const [displayName, setDisplayName] = useState('');
  const [locale, setLocale] = useState('en');
  const [security, setSecurity] = useState<{ active_access_codes: number; security_snapshot: Record<string, unknown> } | null>(null);
  const [msg, setMsg] = useState('');

  useEffect(() => {
    if (!token) return;
    api.companySettingsOrganization(token).then((d) => {
      setDisplayName(d.company.display_name || '');
      setLocale(d.company.locale);
    });
    api.companySettingsSecurity(token).then(setSecurity);
  }, [token]);

  const saveOrg = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!token) return;
    await api.updateCompanySettings(token, { display_name: displayName, locale });
    setMsg('Organization settings saved.');
  };

  const rotate = async () => {
    if (!token || !confirm('Rotate all employee access codes? Admins must redistribute new codes.')) return;
    const res = await api.rotateAccessCodes(token);
    setMsg(`Rotated ${res.codes_rotated} access codes.`);
    api.companySettingsSecurity(token).then(setSecurity);
  };

  return (
    <div className="space-y-6">
      <PageHeader title="Settings" description="Organization profile and security controls." />
      {msg && <p className="rounded-button bg-status-successBg px-4 py-2 text-sm text-status-success">{msg}</p>}

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
            ]}
          />
          <Button type="submit">Save</Button>
        </form>
      </Card>

      <Card title="Security">
        {security && (
          <div className="space-y-4">
            <StatCard label="Active access codes" value={security.active_access_codes} />
            <p className="text-sm text-text-secondary">
              Unrecognized verification attempts (7d):{' '}
              {String(security.security_snapshot?.unrecognized_verification_attempts_7d ?? 0)}
            </p>
            <Button variant="secondary" onClick={rotate}>
              Rotate all access codes
            </Button>
          </div>
        )}
      </Card>
    </div>
  );
}
