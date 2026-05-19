import { useNavigate, Link } from 'react-router-dom';
import { api } from '../lib/api';
import { useAuth } from '../lib/auth';
import { LoginForm } from './LoginForm';

export function PlatformLogin() {
  const { setSession } = useAuth();
  const navigate = useNavigate();

  return (
    <LoginForm
      portalName="Platform Admin"
      tagline="Manage companies, trials, and system health across your Req deployment."
      defaultEmail="admin@reqapp.local"
      footer={
        <>
          Company admin? <Link to="/company/login">Company portal</Link> · <Link to="/reviewer/login">Reviewer</Link>
        </>
      }
      onSubmit={async (email, password) => {
        const data = await api.platformLogin(email, password);
        setSession({ portal: 'platform', token: data.token, user: data.user });
        navigate('/platform/dashboard');
      }}
    />
  );
}
