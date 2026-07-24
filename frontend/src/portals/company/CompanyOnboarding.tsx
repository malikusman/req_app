import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api } from '../../lib/api';
import { useCompanyToken, useAuth } from '../../lib/auth';
import { PageHeader, Card, Input, Select, Button, Skeleton } from '../../components/ui';
import {
  BUSINESS_GOAL_OPTIONS,
  DEPARTMENT_OPTIONS,
  ENGAGEMENT_MODE_OPTIONS,
  INDUSTRY_OPTIONS,
  REGION_OPTIONS,
  REVENUE_BAND_OPTIONS,
  SIZE_BAND_OPTIONS,
  toggleMulti,
} from '../../lib/companyProfileOptions';

export function CompanyOnboarding() {
  const token = useCompanyToken();
  const { session, setSession } = useAuth();
  const navigate = useNavigate();
  const [displayName, setDisplayName] = useState('');
  const [locale, setLocale] = useState('en');
  const [engagementMode, setEngagementMode] = useState('hybrid');
  const [industry, setIndustry] = useState('');
  const [subIndustry, setSubIndustry] = useState('');
  const [sizeBand, setSizeBand] = useState('');
  const [region, setRegion] = useState('');
  const [revenueBand, setRevenueBand] = useState('');
  const [departments, setDepartments] = useState<string[]>([]);
  const [goals, setGoals] = useState<string[]>([]);
  const [knownSystems, setKnownSystems] = useState('');
  const [error, setError] = useState('');
  const [initialLoading, setInitialLoading] = useState(true);
  const [finishing, setFinishing] = useState(false);

  useEffect(() => {
    if (!token) return;
    api
      .companyOnboarding(token)
      .then((d) => {
        setDisplayName(d.company.display_name || '');
        setLocale(d.company.locale || 'en');
        if (d.company.engagement_mode) setEngagementMode(d.company.engagement_mode);
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
      .catch(() => setError('Could not load onboarding progress — defaults shown.'))
      .finally(() => setInitialLoading(false));
  }, [token]);

  const finish = async () => {
    if (!token) return;
    setError('');
    setFinishing(true);
    try {
      await api.updateOnboardingProfile(token, {
        display_name: displayName,
        locale,
        engagement_mode: engagementMode,
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
      await api.completeOnboarding(token);
      if (session?.portal === 'company') {
        setSession({
          ...session,
          company: {
            ...session.company,
            portal_onboarding_completed_at: new Date().toISOString(),
          },
        });
      }
      navigate('/company/dashboard', { replace: true });
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to complete setup');
    } finally {
      setFinishing(false);
    }
  };

  if (initialLoading) {
    return (
      <div className="space-y-6">
        <Skeleton variant="text" />
        <Skeleton variant="card" />
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-xl space-y-6">
      <PageHeader
        title="Confirm company details"
        description="Review your profile from signup, then go to the dashboard to upload documents or invite employees."
      />

      {error ? <p className="text-sm text-status-error">{error}</p> : null}

      <Card>
        <div className="space-y-4">
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
            options={[...ENGAGEMENT_MODE_OPTIONS]}
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

          <Button className="w-full" loading={finishing} onClick={finish}>
            Complete setup
          </Button>
          <p className="m-0 text-center text-xs text-text-secondary">
            Next: upload documents or invite employees from the dashboard.
          </p>
        </div>
      </Card>
    </div>
  );
}
