import { Link } from 'react-router-dom';

export function PlatformDashboard() {
  return (
    <div>
      <h1 style={{ marginTop: 0 }}>Platform Dashboard</h1>
      <p style={{ color: '#64748b' }}>Manage companies, trials, and system health.</p>
      <div className="grid-2" style={{ marginTop: '1.5rem' }}>
        <Link to="/platform/companies" className="card" style={{ display: 'block', textDecoration: 'none', color: 'inherit' }}>
          <h3 style={{ margin: '0 0 0.5rem' }}>Companies</h3>
          <p style={{ margin: 0, color: '#64748b', fontSize: '0.9rem' }}>Create and manage client organizations</p>
        </Link>
        <Link to="/platform/trials" className="card" style={{ display: 'block', textDecoration: 'none', color: 'inherit' }}>
          <h3 style={{ margin: '0 0 0.5rem' }}>Trial management</h3>
          <p style={{ margin: 0, color: '#64748b', fontSize: '0.9rem' }}>Extend trials before clients churn</p>
        </Link>
      </div>
    </div>
  );
}
