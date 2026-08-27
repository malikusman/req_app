import { useEffect, useMemo, useState } from 'react';
import { Outlet, useLocation, useNavigate } from 'react-router-dom';
import { useAuth, useConsultantToken } from '../../lib/auth';
import { api, type ConsultantDashboardPayload } from '../../lib/api';
import { PortalShell } from '../../components/layout/PortalShell';
import { consultantNavItems } from './nav';
import { usePageMeta } from '../../lib/usePageMeta';

export function ConsultantLayout() {
  const { session, logout } = useAuth();
  const token = useConsultantToken();
  const navigate = useNavigate();
  const { pathname } = useLocation();
  const { title } = usePageMeta('Consultant');
  const [payload, setPayload] = useState<ConsultantDashboardPayload | null>(null);

  // Feed the sidebar assignments from the dashboard payload (mirrors CompanyLayout).
  // Partial-failure safe: on error we keep null and consultantNavItems falls back
  // to the static base nav (Home / Inbox / Profile).
  useEffect(() => {
    if (!token) return;
    api
      .consultantDashboard(token)
      .then(setPayload)
      .catch(() => setPayload(null));
  }, [token]);

  const nav = useMemo(() => consultantNavItems(payload), [payload]);

  if (session?.portal !== 'consultant') return null;

  const fullBleed = /\/reports\/\d+\/review$/.test(pathname);

  return (
    <PortalShell
      portal="consultant"
      navItems={nav}
      fullBleed={fullBleed}
      title={title}
      userMenu={{
        name: session.user.name,
        email: session.user.email,
        roleBadge: 'Consultant',
        onLogout: () => {
          logout();
          navigate('/consultant/login');
        },
      }}
    >
      <Outlet />
    </PortalShell>
  );
}
