import { Outlet, NavLink, useNavigate } from 'react-router-dom';
import { useAuth, endImpersonation } from '../../lib/auth';
import { NotificationBell } from '../../components/NotificationBell';
import { ImpersonationBanner } from '../../components/ImpersonationBanner';

export function CompanyLayout() {
  const { session, setSession, logout } = useAuth();
  const navigate = useNavigate();
  const name = session?.portal === 'company' ? session.user.name : '';
  const companyName = session?.portal === 'company' ? session.company.name : '';
  const impersonating = session?.portal === 'company' && session.impersonating;

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
    <div className="app-shell">
      <ImpersonationBanner />
      <nav className="nav" style={{ background: '#1e3a5f' }}>
        <span className="nav-brand">{companyName || 'Company Portal'}</span>
        <div className="nav-links">
          <NavLink to="/company/dashboard">Dashboard</NavLink>
          <NavLink to="/company/employees">Employees</NavLink>
          <NavLink to="/company/documents">Documents</NavLink>
          <NavLink to="/company/recommendations">Recommendations</NavLink>
          <NavLink to="/company/reports">Reports</NavLink>
          <NavLink to="/company/billing">Billing</NavLink>
          <NavLink to="/company/discovery-questions">Questions</NavLink>
          <NavLink to="/company/settings">Settings</NavLink>
          {!impersonating && <NavLink to="/company/onboarding">Setup</NavLink>}
          <NotificationBell />
          <span style={{ color: '#94a3b8', fontSize: '0.85rem' }}>{name}</span>
          <button
            type="button"
            className="btn btn-ghost"
            style={{ color: '#fff', borderColor: '#475569' }}
            onClick={handleLogout}
          >
            {impersonating ? 'Exit impersonation' : 'Log out'}
          </button>
        </div>
      </nav>
      <main className="main">
        <Outlet />
      </main>
    </div>
  );
}
