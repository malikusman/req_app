import { useEffect, useMemo, useState } from 'react';
import { Outlet, useNavigate } from 'react-router-dom';
import { useAuth, usePlatformToken } from '../../lib/auth';
import { api } from '../../lib/api';
import { PortalShell } from '../../components/layout/PortalShell';
import { platformNavItems, type PlatformNavCounts } from './nav';
import { usePageMeta } from '../../lib/usePageMeta';

export function PlatformLayout() {
  const { session, logout } = useAuth();
  const token = usePlatformToken();
  const navigate = useNavigate();
  const { title } = usePageMeta('Platform');
  const [counts, setCounts] = useState<PlatformNavCounts>({});

  // Feed the sidebar attention badges from the lightest pending-work endpoints.
  // Partial-failure safe: each fetch is independent and on error we leave that
  // count undefined, so platformNavItems falls back to no badge (static nav).
  useEffect(() => {
    if (!token) return;
    api
      .platformRegistrations(token, 'pending')
      .then((d) => {
        const pending =
          d.company_registrations.filter((r) => r.status === 'pending').length +
          d.reviewer_applications.filter((r) => r.status === 'pending').length;
        setCounts((prev) => ({ ...prev, registrations: pending }));
      })
      .catch(() => undefined);
    api
      .platformCatalogCandidates(token, { reviewStatus: 'pending', perPage: 1 })
      .then((d) => setCounts((prev) => ({ ...prev, candidates: d.pagination?.total ?? 0 })))
      .catch(() => undefined);
    api
      .platformPendingReports(token)
      .then((d) => setCounts((prev) => ({ ...prev, approvals: d.reports.length })))
      .catch(() => undefined);
  }, [token]);

  const nav = useMemo(() => platformNavItems(counts), [counts]);

  if (session?.portal !== 'platform') return null;

  return (
    <PortalShell
      portal="platform"
      navItems={nav}
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
