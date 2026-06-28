import { Outlet, useLocation, useNavigate } from 'react-router-dom';
import { useAuth } from '../../lib/auth';
import { PortalShell } from '../../components/layout/PortalShell';
import { navItems } from './nav';
import { usePageMeta } from '../../lib/usePageMeta';

export function ReviewerLayout() {
  const { session, logout } = useAuth();
  const navigate = useNavigate();
  const { pathname } = useLocation();
  const { title } = usePageMeta('Reviewer');

  if (session?.portal !== 'reviewer') return null;

  const fullBleed = /\/reports\/\d+\/review$/.test(pathname);

  return (
    <PortalShell
      portal="reviewer"
      navItems={navItems}
      fullBleed={fullBleed}
      title={title}
      userMenu={{
        name: session.user.name,
        email: session.user.email,
        roleBadge: 'Reviewer',
        onLogout: () => {
          logout();
          navigate('/reviewer/login');
        },
      }}
    >
      <Outlet />
    </PortalShell>
  );
}
