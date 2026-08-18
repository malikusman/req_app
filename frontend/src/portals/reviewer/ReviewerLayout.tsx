import { useEffect, useMemo, useState } from 'react';
import { Outlet, useLocation, useNavigate } from 'react-router-dom';
import { useAuth, useReviewerToken } from '../../lib/auth';
import { api, type ReviewerDashboardPayload } from '../../lib/api';
import { PortalShell } from '../../components/layout/PortalShell';
import { reviewerNavItems } from './nav';
import { usePageMeta } from '../../lib/usePageMeta';

export function ReviewerLayout() {
  const { session, logout } = useAuth();
  const token = useReviewerToken();
  const navigate = useNavigate();
  const { pathname } = useLocation();
  const { title } = usePageMeta('Reviewer');
  const [payload, setPayload] = useState<ReviewerDashboardPayload | null>(null);

  // Feed the sidebar assignments from the dashboard payload (mirrors CompanyLayout).
  // Partial-failure safe: on error we keep null and reviewerNavItems falls back
  // to the static base nav (Home / Inbox / Profile).
  useEffect(() => {
    if (!token) return;
    api
      .reviewerDashboard(token)
      .then(setPayload)
      .catch(() => setPayload(null));
  }, [token]);

  const nav = useMemo(() => reviewerNavItems(payload), [payload]);

  if (session?.portal !== 'reviewer') return null;

  const fullBleed = /\/reports\/\d+\/review$/.test(pathname);

  return (
    <PortalShell
      portal="reviewer"
      navItems={nav}
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
