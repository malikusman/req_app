import { useState, type FormEvent } from 'react';
import { Link } from 'react-router-dom';
import { AuthLayout } from '../components/layout/AuthLayout';
import { ShineBorder } from '../components/motion';
import { Input } from '../components/ui/Input';
import { Select } from '../components/ui/Select';
import { Button } from '../components/ui/Button';
import { api } from '../lib/api';
import {
  BUSINESS_GOAL_OPTIONS,
  DEPARTMENT_OPTIONS,
  ENGAGEMENT_MODE_OPTIONS,
  INDUSTRY_OPTIONS,
  REGION_OPTIONS,
  REVENUE_BAND_OPTIONS,
  SIZE_BAND_OPTIONS,
  toggleMulti,
} from '../lib/companyProfileOptions';

export function CompanySignupPage() {
  const [companyName, setCompanyName] = useState('');
  const [adminName, setAdminName] = useState('');
  const [adminEmail, setAdminEmail] = useState('');
  const [roleTitle, setRoleTitle] = useState('');
  const [industry, setIndustry] = useState('');
  const [subIndustry, setSubIndustry] = useState('');
  const [sizeBand, setSizeBand] = useState('');
  const [region, setRegion] = useState('');
  const [regionOther, setRegionOther] = useState('');
  const [revenueBand, setRevenueBand] = useState('');
  const [departments, setDepartments] = useState<string[]>([]);
  const [goals, setGoals] = useState<string[]>([]);
  const [knownSystems, setKnownSystems] = useState('');
  const [engagementMode, setEngagementMode] = useState('hybrid');
  const [website, setWebsite] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const [done, setDone] = useState(false);

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError('');
    if (!industry) {
      setError('Please select an industry.');
      return;
    }
    if (!sizeBand) {
      setError('Please select company size.');
      return;
    }
    setLoading(true);
    try {
      const resolvedRegion = region === 'Other' ? regionOther.trim() || 'Other' : region || undefined;
      await api.publicCompanyRegistration({
        company_name: companyName,
        admin_name: adminName,
        admin_email: adminEmail,
        role_title: roleTitle || undefined,
        engagement_mode: engagementMode,
        company_profile: {
          industry,
          sub_industry: subIndustry.trim() || undefined,
          size_band: sizeBand,
          region: resolvedRegion,
          annual_revenue_band: revenueBand || undefined,
          org_departments: departments,
          business_goals: goals,
        },
        known_systems: knownSystems
          .split(/[,;\n]+/)
          .map((s) => s.trim())
          .filter(Boolean),
        website: website || undefined,
      });
      setDone(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Signup failed');
    } finally {
      setLoading(false);
    }
  };

  return (
    <AuthLayout
      portal="company"
      portalName="Worktruth — Company"
      tagline="Request a company account. A platform admin will approve access before you can sign in."
    >
      <div className="mb-6">
        <h1 className="font-display text-page-title text-text-primary m-0">Create a company account</h1>
        <p className="mt-1 text-sm text-text-secondary">
          Already approved? <Link to="/company/login">Sign in</Link>
        </p>
      </div>

      <ShineBorder className="shadow-card">
        {done ? (
          <div className="space-y-3 p-6">
            <p className="m-0 font-display text-lg text-text-primary">Request received</p>
            <p className="m-0 text-sm text-text-secondary">
              Check your email for confirmation. We&apos;ll send a set-password link once a platform admin
              approves your account.
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

            <p className="m-0 text-xs font-medium uppercase tracking-wide text-text-secondary">Contact</p>
            <Input
              label="Company name"
              id="company_name"
              value={companyName}
              onChange={(e) => setCompanyName(e.target.value)}
              required
            />
            <Input
              label="Your name"
              id="admin_name"
              value={adminName}
              onChange={(e) => setAdminName(e.target.value)}
              required
            />
            <Input
              label="Work email"
              id="admin_email"
              type="email"
              value={adminEmail}
              onChange={(e) => setAdminEmail(e.target.value)}
              required
            />
            <Input
              label="Role (optional)"
              id="role_title"
              value={roleTitle}
              onChange={(e) => setRoleTitle(e.target.value)}
            />

            <p className="m-0 pt-2 text-xs font-medium uppercase tracking-wide text-text-secondary">Company profile</p>
            <Select
              label="Industry"
              id="industry"
              value={industry}
              onChange={(e) => setIndustry(e.target.value)}
              options={[{ value: '', label: 'Select industry' }, ...INDUSTRY_OPTIONS]}
              required
            />
            <Input
              label="Sub-industry / focus (optional)"
              id="sub_industry"
              value={subIndustry}
              onChange={(e) => setSubIndustry(e.target.value)}
              placeholder="e.g. last-mile freight"
            />
            <Select
              label="Company size"
              id="size_band"
              value={sizeBand}
              onChange={(e) => setSizeBand(e.target.value)}
              options={[{ value: '', label: 'Select size' }, ...SIZE_BAND_OPTIONS]}
              required
            />
            <Select
              label="Region"
              id="region"
              value={region}
              onChange={(e) => setRegion(e.target.value)}
              options={[{ value: '', label: 'Select region' }, ...REGION_OPTIONS]}
            />
            {region === 'Other' ? (
              <Input
                label="Specify region"
                value={regionOther}
                onChange={(e) => setRegionOther(e.target.value)}
              />
            ) : null}
            <Select
              label="Annual revenue (optional)"
              id="revenue"
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
              label="Known systems (optional)"
              id="known_systems"
              value={knownSystems}
              onChange={(e) => setKnownSystems(e.target.value)}
              placeholder="SAP, Excel, Slack"
            />
            <Select
              label="Discovery approach"
              id="engagement_mode"
              value={engagementMode}
              onChange={(e) => setEngagementMode(e.target.value)}
              options={[...ENGAGEMENT_MODE_OPTIONS]}
            />
            <p className="m-0 text-xs text-text-secondary">
              You can change this later. Documents-first is fine if you want a baseline before inviting employees.
            </p>

            {/* Honeypot */}
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
              Request access
            </Button>
          </form>
        )}
      </ShineBorder>
    </AuthLayout>
  );
}
