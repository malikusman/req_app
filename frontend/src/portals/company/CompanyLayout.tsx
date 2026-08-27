import { useEffect, useMemo, useState } from 'react';
import { Outlet, useNavigate } from 'react-router-dom';
import { useAuth, endImpersonation, useCompanyToken } from '../../lib/auth';
import { api, type CompanyDashboardPayload } from '../../lib/api';
import { PortalShell } from '../../components/layout/PortalShell';
import { companyNavItems } from './nav';
import { NotificationBell } from '../../components/NotificationBell';
import { ImpersonationBanner } from '../../components/ImpersonationBanner';
import { usePageMeta } from '../../lib/usePageMeta';

export function CompanyLayout() {
  const { session, setSession, logout } = useAuth();
  const token = useCompanyToken();
  const navigate = useNavigate();
  usePageMeta('Company');
  const [integrations, setIntegrations] = useState<CompanyDashboardPayload['integrations']>();
  const [navCounts, setNavCounts] = useState<{
    profilePercent?: number;
    reportVersion?: number | null;
    consultantQuestions?: number;
  }>({});

  const impersonating = Boolean(session?.portal === 'company' && session.impersonating);

  useEffect(() => {
    if (!token) return;
    api
      .companyDashboard(token)
      .then((d) => {
        setIntegrations(d.integrations);
        setNavCounts((prev) => ({
          ...prev,
          profilePercent: d.questionnaire_completion_percent,
          reportVersion: d.latest_report?.version ?? null,
        }));
      })
      .catch(() => undefined);
    // Badge on the "Consultant questions" item must match its destination
    // (/company/outreaches): count outreaches actually waiting on the admin.
    api
      .companyOutreaches(token)
      .then((d) => {
        const needsInput = (d.outreaches || []).filter(
          (o) => o.status === 'pending_admin_approval' || (o.recipient_type === 'company_admin' && o.status === 'sent')
        ).length;
        setNavCounts((prev) => ({ ...prev, consultantQuestions: needsInput }));
      })
      .catch(() => undefined);
  }, [token]);

  const nav = useMemo(() => companyNavItems(navCounts), [navCounts]);


  const integrationWarnings = useMemo(() => {
    if (!integrations) return [];
    const warnings: string[] = [];
    if (!integrations.openai_configured) {
      warnings.push(
        integrations.mocks_allowed
          ? 'OpenAI is not configured — multimodal AI uses local mocks (dev only).'
          : 'OpenAI is not configured — AI features will fail until OPENAI_API_KEY is set.'
      );
    }
    if (!integrations.gotenberg_ok) {
      warnings.push(
        integrations.mocks_allowed
          ? 'PDF service (Gotenberg) is down — reports may store as HTML.'
          : 'PDF service (Gotenberg) is down — report generation will fail.'
      );
    }
    if (!integrations.stripe_configured) {
      warnings.push(
        integrations.mocks_allowed
          ? 'Stripe is not configured — billing uses mock checkout (dev only).'
          : 'Stripe is not configured — paid upgrades are unavailable.'
      );
    }
    return warnings;
  }, [integrations]);

  if (session?.portal !== 'company') return null;

  const companyName = session.company.name;

  const handleLogout = () => {
    if (impersonating) {
      endImpersonation(setSession);
      navigate('/platform/companies');
      return;
    }
    logout();
    navigate('/company/login');
  };

  return (
    <>
      <ImpersonationBanner />
      {integrationWarnings.length > 0 && (
        <div className="border-b border-warning/30 bg-warning/10 px-4 py-2 text-sm text-warning md:ml-sidebar" role="status">
          {integrationWarnings.map((w) => (
            <p key={w} className="leading-snug">
              {w}
            </p>
          ))}
        </div>
      )}
      <PortalShell
        portal="company"
        logo={companyName}
        navItems={nav}
        title={companyName}
        topBarActions={<NotificationBell />}
        userMenu={{
          name: session.user.name,
          email: session.user.email,
          roleBadge: impersonating ? 'Impersonating' : 'Company Admin',
          onLogout: handleLogout,
          logoutLabel: impersonating ? 'Exit impersonation' : 'Log out',
        }}
      >
        <Outlet />
      </PortalShell>
    </>
  );
}
