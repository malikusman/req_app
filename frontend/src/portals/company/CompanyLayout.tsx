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
  const { title } = usePageMeta('Company');
  const [docsFirstPhase, setDocsFirstPhase] = useState(false);
  const [onboardingComplete, setOnboardingComplete] = useState(false);
  const [integrations, setIntegrations] = useState<CompanyDashboardPayload['integrations']>();

  useEffect(() => {
    if (!token) return;
    api
      .companyDashboard(token)
      .then((d) => {
        setDocsFirstPhase(Boolean(d.docs_first_phase ?? d.company.docs_first_phase));
        setOnboardingComplete(Boolean(d.company.onboarding_complete));
        setIntegrations(d.integrations);
      })
      .catch(() => undefined);
  }, [token]);

  const nav = useMemo(
    () => companyNavItems({ docsFirstPhase, onboardingComplete }),
    [docsFirstPhase, onboardingComplete]
  );

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

  const impersonating = session.impersonating;
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
        <div className="border-b border-amber-200 bg-amber-50 px-4 py-2 text-sm text-amber-950" role="status">
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
        navItems={nav.filter((item) => !impersonating || item.to !== '/company/onboarding')}
        title={title}
        subtitle={companyName}
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
