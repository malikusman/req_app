import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { ClipboardList } from 'lucide-react';
import { api } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { PageHeader, Card, Input, Select, Button, StatCard, Skeleton } from '../../components/ui';
import { ConfirmDialog } from '../../components/ui/ConfirmDialog';
import { useToast } from '../../components/ui/ToastProvider';
import { SETTINGS_SECONDARY_LINKS } from './nav';

export function CompanySettings() {
  const token = useCompanyToken();
  const { toast } = useToast();
  const [displayName, setDisplayName] = useState('');
  const [locale, setLocale] = useState('en');
  const [websiteUrl, setWebsiteUrl] = useState('');
  const [researchBusy, setResearchBusy] = useState(false);
  const [security, setSecurity] = useState<{
    active_access_codes: number;
    security_snapshot: Record<string, unknown>;
  } | null>(null);
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
        setWebsiteUrl(d.company.website_url || '');
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
        website_url: websiteUrl.trim() || null,
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

  const refreshResearch = async () => {
    if (!token) return;
    setResearchBusy(true);
    try {
      await api.refreshCompanyWebResearch(token);
      toast({
        variant: 'success',
        title: 'Research queued',
        description: 'Website research will refresh in the background for agents and reports.',
      });
    } catch (err) {
      toast({
        variant: 'error',
        title: 'Research failed',
        description: err instanceof Error ? err.message : 'Could not queue website research.',
      });
    } finally {
      setResearchBusy(false);
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

  const canRotate = (security?.active_access_codes ?? 0) > 0;

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
              Industry, systems, goals, and other business details are edited in the guided questionnaire.
            </p>
          </div>
          <Link to="/company/onboarding">
            <Button variant="secondary" icon={<ClipboardList className="h-4 w-4" />}>
              Open questionnaire
            </Button>
          </Link>
        </div>
      </Card>

      <Card title="Organization">
        <form onSubmit={saveOrg} className="max-w-md space-y-4">
          <Input label="Display name" value={displayName} onChange={(e) => setDisplayName(e.target.value)} />
          <Input
            label="Company website"
            value={websiteUrl}
            onChange={(e) => setWebsiteUrl(e.target.value)}
            placeholder="https://example.com"
          />
          <p className="m-0 text-xs text-muted-foreground">
            Used by discovery agents and optional website research for reports. Distinct from the signup spam honeypot field.
          </p>
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
          <div className="flex flex-wrap gap-2">
            <Button type="submit">Save</Button>
            <Button
              type="button"
              variant="secondary"
              loading={researchBusy}
              disabled={!websiteUrl.trim()}
              onClick={refreshResearch}
            >
              Refresh website research
            </Button>
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
              Access codes let invited employees unlock WhatsApp or web discovery. Each employee gets a code when
              invited.
            </p>
            <StatCard label="Active access codes" value={security.active_access_codes} />
            <p className="text-sm text-text-secondary">
              Unrecognized verification attempts (7d):{' '}
              {String(security.security_snapshot?.unrecognized_verification_attempts_7d ?? 0)}
            </p>
            {canRotate ? (
              <Button variant="secondary" onClick={() => setRotateOpen(true)}>
                Rotate all access codes
              </Button>
            ) : (
              <div className="space-y-2">
                <Button variant="secondary" disabled>
                  Rotate all access codes
                </Button>
                <p className="m-0 text-sm text-text-secondary">
                  Invite employees first — there are no active codes to rotate.{' '}
                  <Link to="/company/employees" className="font-medium text-primary hover:underline">
                    Invite employees
                  </Link>
                </p>
              </div>
            )}
          </div>
        )}
      </Card>

      <ConfirmDialog
        open={rotateOpen}
        onClose={() => setRotateOpen(false)}
        onConfirm={rotate}
        title="Rotate all access codes?"
        description="Invalidates unused codes immediately. Admins must redistribute new codes to employees."
        confirmLabel="Rotate codes"
        variant="danger"
      />
    </div>
  );
}
