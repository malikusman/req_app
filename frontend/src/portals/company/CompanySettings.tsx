import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { api } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { PageHeader, Card, Input, Select, Button, StatCard, Skeleton } from '../../components/ui';
import { ConfirmDialog } from '../../components/ui/ConfirmDialog';
import { useToast } from '../../components/ui/ToastProvider';
import { SETTINGS_SECONDARY_LINKS } from './nav';
import {
  BUSINESS_GOAL_OPTIONS,
  DEPARTMENT_OPTIONS,
  INDUSTRY_OPTIONS,
  REGION_OPTIONS,
  REVENUE_BAND_OPTIONS,
  SIZE_BAND_OPTIONS,
  toggleMulti,
} from '../../lib/companyProfileOptions';

export function CompanySettings() {
  const token = useCompanyToken();
  const { toast } = useToast();
  const [displayName, setDisplayName] = useState('');
  const [locale, setLocale] = useState('en');
  const [industry, setIndustry] = useState('');
  const [subIndustry, setSubIndustry] = useState('');
  const [sizeBand, setSizeBand] = useState('');
  const [region, setRegion] = useState('');
  const [revenueBand, setRevenueBand] = useState('');
  const [departments, setDepartments] = useState<string[]>([]);
  const [goals, setGoals] = useState<string[]>([]);
  const [knownSystems, setKnownSystems] = useState('');
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
        const profile = d.company.company_profile || {};
        setIndustry(profile.industry || '');
        setSubIndustry(profile.sub_industry || '');
        setSizeBand(profile.size_band || '');
        setRegion(profile.region || profile.country || '');
        setRevenueBand(profile.annual_revenue_band || '');
        setDepartments(Array.isArray(profile.org_departments) ? profile.org_departments : []);
        setGoals(
          Array.isArray(profile.business_goals)
            ? profile.business_goals
            : profile.business_goals
              ? [profile.business_goals]
              : []
        );
        setKnownSystems((d.company.known_systems || []).join(', '));
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
        company_profile: {
          industry: industry || undefined,
          sub_industry: subIndustry.trim() || undefined,
          size_band: sizeBand || undefined,
          region: region.trim() || undefined,
          annual_revenue_band: revenueBand || undefined,
          org_departments: departments,
          business_goals: goals,
        },
        known_systems: knownSystems
          .split(/[,;\n]+/)
          .map((s) => s.trim())
          .filter(Boolean),
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

  const canRotate = (security?.active_access_codes ?? 0) > 0;

  return (
    <div className="space-y-6">
      <PageHeader title="Settings" description="Organization profile, security, and secondary tools." />

      {loadError && (
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-button border border-status-error/30 bg-status-errorBg px-4 py-3 text-sm text-status-error">
          <span>{loadError}</span>
          <Button size="sm" variant="secondary" onClick={load}>
            Retry
          </Button>
        </div>
      )}

      <Card title="More tools">
        <div className="grid gap-3 sm:grid-cols-2">
          <Link
            to="/company/onboarding"
            className="flex items-start gap-3 rounded-lg border border-border p-3 transition-colors hover:border-primary/40 hover:bg-muted/40 sm:col-span-2"
          >
            <div className="min-w-0">
              <p className="m-0 font-medium text-foreground">Company profile questionnaire</p>
              <p className="m-0 text-sm text-muted-foreground">
                Resume the guided profile — helps Worktruth analyze your business more accurately.
              </p>
            </div>
          </Link>
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
            label="Industry"
            value={industry}
            onChange={(e) => setIndustry(e.target.value)}
            options={[{ value: '', label: 'Select industry' }, ...INDUSTRY_OPTIONS]}
          />
          <Input
            label="Sub-industry / focus (optional)"
            value={subIndustry}
            onChange={(e) => setSubIndustry(e.target.value)}
          />
          <Select
            label="Company size"
            value={sizeBand}
            onChange={(e) => setSizeBand(e.target.value)}
            options={[{ value: '', label: 'Prefer not to say' }, ...SIZE_BAND_OPTIONS]}
          />
          <Select
            label="Region"
            value={region}
            onChange={(e) => setRegion(e.target.value)}
            options={[
              { value: '', label: 'Select region' },
              ...REGION_OPTIONS.filter((r) => r.value !== 'Other'),
              ...(region && !REGION_OPTIONS.some((r) => r.value === region)
                ? [{ value: region, label: region }]
                : []),
              { value: 'Other', label: 'Other' },
            ]}
          />
          <Select
            label="Annual revenue (optional)"
            value={revenueBand}
            onChange={(e) => setRevenueBand(e.target.value)}
            options={[...REVENUE_BAND_OPTIONS]}
          />
          <fieldset className="space-y-2">
            <legend className="text-sm font-medium text-text-primary">Primary departments</legend>
            <div className="flex flex-wrap gap-2">
              {DEPARTMENT_OPTIONS.map((dept) => {
                const active = departments.includes(dept);
                return (
                  <button
                    key={dept}
                    type="button"
                    onClick={() => setDepartments((prev) => toggleMulti(prev, dept))}
                    className={`rounded-button border px-3 py-1.5 text-xs ${
                      active
                        ? 'border-accent bg-accent/10 text-accent'
                        : 'border-border text-text-secondary hover:border-accent/40'
                    }`}
                  >
                    {dept}
                  </button>
                );
              })}
            </div>
          </fieldset>
          <fieldset className="space-y-2">
            <legend className="text-sm font-medium text-text-primary">Business goals</legend>
            <div className="flex flex-wrap gap-2">
              {BUSINESS_GOAL_OPTIONS.map((goal) => {
                const active = goals.includes(goal.value);
                return (
                  <button
                    key={goal.value}
                    type="button"
                    onClick={() => setGoals((prev) => toggleMulti(prev, goal.value))}
                    className={`rounded-button border px-3 py-1.5 text-xs ${
                      active
                        ? 'border-accent bg-accent/10 text-accent'
                        : 'border-border text-text-secondary hover:border-accent/40'
                    }`}
                  >
                    {goal.label}
                  </button>
                );
              })}
            </div>
          </fieldset>
          <Input
            label="Known systems"
            value={knownSystems}
            onChange={(e) => setKnownSystems(e.target.value)}
            placeholder="SAP, Excel, Slack"
          />
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
