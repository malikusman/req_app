import { Outlet, useNavigate } from 'react-router-dom';
import { useAuth, endImpersonation } from '../../lib/auth';
import { PortalShell } from '../../components/layout/PortalShell';
import { navItems } from './nav';
import { NotificationBell } from '../../components/NotificationBell';
import { ImpersonationBanner } from '../../components/ImpersonationBanner';
import { usePageMeta } from '../../lib/usePageMeta';

export function CompanyLayout() {
  const { session, setSession, logout } = useAuth();
  const navigate = useNavigate();
  const { title } = usePageMeta('Company');

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
      <PortalShell
        portal="company"
        logo={companyName}
        navItems={navItems.filter((item) => !impersonating || item.to !== '/company/onboarding')}
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
