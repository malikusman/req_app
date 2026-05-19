import { Outlet, useNavigate, useParams } from 'react-router-dom';
import { useAuth } from '../../lib/auth';
import { PortalShell } from '../../components/layout/PortalShell';
import { navItems, companyNavItems } from './nav';
import { usePageMeta } from '../../lib/usePageMeta';

export function ReviewerLayout() {
  const { session, logout } = useAuth();
  const navigate = useNavigate();
  const { companyId } = useParams();
  const { title } = usePageMeta('Reviewer');

  if (session?.portal !== 'reviewer') return null;

  const items = companyId ? [...navItems, ...companyNavItems(Number(companyId))] : navItems;

  return (
    <PortalShell
      portal="reviewer"
      navItems={items}
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
