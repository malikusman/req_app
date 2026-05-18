import { Outlet, NavLink, useNavigate } from 'react-router-dom';
import { useAuth } from '../../lib/auth';

export function PlatformLayout() {
  const { session, logout } = useAuth();
  const navigate = useNavigate();
  const name = session?.portal === 'platform' ? session.user.name : '';

  const handleLogout = () => {
    logout();
    navigate('/platform/login');
  };

  return (
    <div className="app-shell">
      <nav className="nav">
        <span className="nav-brand">Req — Platform</span>
        <div className="nav-links">
          <NavLink to="/platform/dashboard">Dashboard</NavLink>
          <NavLink to="/platform/companies">Companies</NavLink>
          <NavLink to="/platform/reviewers">Reviewers</NavLink>
          <NavLink to="/platform/trials">Trials</NavLink>
          <NavLink to="/platform/playbooks">Playbooks</NavLink>
          <NavLink to="/platform/solutions">Solutions</NavLink>
          <NavLink to="/platform/system">System</NavLink>
          <NavLink to="/platform/monitoring">Monitoring</NavLink>
          <span style={{ color: '#94a3b8', fontSize: '0.85rem' }}>{name}</span>
          <button
            type="button"
            className="btn btn-ghost"
            style={{ color: '#fff', borderColor: '#475569' }}
            onClick={handleLogout}
          >
            Log out
          </button>
        </div>
      </nav>
      <main className="main">
        <Outlet />
      </main>
    </div>
  );
}
