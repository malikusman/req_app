import { Outlet, NavLink, useNavigate, useParams } from 'react-router-dom';
import { useAuth } from '../../lib/auth';

export function ReviewerLayout() {
  const { session, logout } = useAuth();
  const navigate = useNavigate();
  const { companyId } = useParams();
  const name = session?.portal === 'reviewer' ? session.user.name : '';

  const handleLogout = () => {
    logout();
    navigate('/reviewer/login');
  };

  return (
    <div className="app-shell">
      <nav className="nav" style={{ background: '#4c1d95' }}>
        <span className="nav-brand">Req — Reviewer</span>
        <div className="nav-links">
          <NavLink to="/reviewer/dashboard">Dashboard</NavLink>
          {companyId && (
            <>
              <NavLink to={`/reviewer/companies/${companyId}`}>Company</NavLink>
              <NavLink to={`/reviewer/companies/${companyId}/conversations`}>Conversations</NavLink>
              <NavLink to={`/reviewer/companies/${companyId}/chat`}>Co-reviewer chat</NavLink>
            </>
          )}
          <span style={{ color: '#c4b5fd', fontSize: '0.85rem' }}>{name}</span>
          <button
            type="button"
            className="btn btn-ghost"
            style={{ color: '#fff', borderColor: '#6d28d9' }}
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
