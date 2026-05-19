import { Outlet, useNavigate } from 'react-router-dom';
import { useAuth } from '../../lib/auth';
import { PortalShell } from '../../components/layout/PortalShell';
import { navItems } from './nav';
import { usePageMeta } from '../../lib/usePageMeta';

export function PlatformLayout() {
  const { session, logout } = useAuth();
  const navigate = useNavigate();
  const { title } = usePageMeta('Platform');

  if (session?.portal !== 'platform') return null;

  return (
    <PortalShell
      portal="platform"
      navItems={navItems}
      title={title}
      userMenu={{
        name: session.user.name,
        email: session.user.email,
        roleBadge: session.user.role,
        onLogout: () => {
          logout();
          navigate('/platform/login');
        },
      }}
    >
      <Outlet />
    </PortalShell>
  );
}
