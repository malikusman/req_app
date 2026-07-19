import { useEffect, useState } from 'react';
import { api } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { PageHeader, Card, Input, Select, Button, StatCard, Skeleton } from '../../components/ui';
import { ConfirmDialog } from '../../components/ui/ConfirmDialog';
import { useToast } from '../../components/ui/ToastProvider';

export function CompanySettings() {
  const token = useCompanyToken();
  const { toast } = useToast();
  const [displayName, setDisplayName] = useState('');
  const [locale, setLocale] = useState('en');
  const [engagementMode, setEngagementMode] = useState('hybrid');
  const [security, setSecurity] = useState<{ active_access_codes: number; security_snapshot: Record<string, unknown> } | null>(null);
  const [rotateOpen, setRotateOpen] = useState(false);
  const [loadError, setLoadError] = useState('');

  const load = () => {
    if (!token) return;
    setLoadError('');
    api
      .companySettingsOrganization(token)
      .then((d) => {
        setDisplayName(d.company.display_name || '');
        setLocale(d.company.locale);
        const mode = (d.settings?.engagement_mode as string) || 'hybrid';
        setEngagementMode(mode);
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
        engagement_mode: engagementMode,
      });
      toast({ variant: 'success', title: 'Saved', description: 'Organization settings updated.' });
    } catch (err) {
      toast({
        variant: 'error',
        title: 'Save failed',
        description: err instanceof Error ? err.message : 'Could not update organization settings.',
      });
    }
  };

  const rotate = async () => {
    if (!token) return;
    try {
      const res = await api.rotateAccessCodes(token);
      setRotateOpen(false);
      toast({
        variant: 'success',
        title: 'Access codes rotated',
        description: `${res.codes_rotated} codes updated — redistribute privately.`,
      });
      api.companySettingsSecurity(token).then(setSecurity).catch(() => undefined);
    } catch (err) {
      setRotateOpen(false);
      toast({
        variant: 'error',
        title: 'Rotation failed',
        description: err instanceof Error ? err.message : 'Could not rotate access codes.',
      });
    }
  };

  return (
    <div className="space-y-6">
      <PageHeader title="Settings" description="Organization profile and security controls." />

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
          <Select
            label="Discovery approach"
            value={engagementMode}
            onChange={(e) => setEngagementMode(e.target.value)}
            options={[
              { value: 'hybrid', label: 'Documents + employees (recommended)' },
              { value: 'documents', label: 'Documents only for now' },
              { value: 'interview', label: 'Employee interviews focus' },
            ]}
          />
          <p className="text-xs text-text-secondary">
            Documents-only emphasizes the baseline path in the portal. Inviting employees automatically switches to
            hybrid so interviews strengthen the same signals.
          </p>
          <Button type="submit">Save</Button>
        </form>
      </Card>

      <Card title="Security">
        {!security ? (
          <div className="space-y-4">
            <Skeleton variant="text" />
            <Skeleton variant="text" />
          </div>
        ) : (
          <div className="space-y-4">
            <StatCard label="Active access codes" value={security.active_access_codes} />
            <p className="text-sm text-text-secondary">
              Unrecognized verification attempts (7d):{' '}
              {String(security.security_snapshot?.unrecognized_verification_attempts_7d ?? 0)}
            </p>
            <Button variant="secondary" onClick={() => setRotateOpen(true)}>
              Rotate all access codes
            </Button>
          </div>
        )}
      </Card>

      <ConfirmDialog
        open={rotateOpen}
        onClose={() => setRotateOpen(false)}
        onConfirm={rotate}
        title="Rotate all access codes?"
        description="Admins must redistribute new codes to employees. Existing codes stop working immediately."
        confirmLabel="Rotate codes"
        variant="danger"
      />
    </div>
  );
}
