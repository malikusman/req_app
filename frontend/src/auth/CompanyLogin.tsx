import { useNavigate, Link } from 'react-router-dom';
import { api } from '../lib/api';
import { useAuth } from '../lib/auth';
import { LoginForm } from './LoginForm';

export function CompanyLogin() {
  const { setSession } = useAuth();
  const navigate = useNavigate();

  return (
    <LoginForm
      portalName="Company Portal"
      tagline="Run workflow discovery and intelligence for your organization."
      defaultEmail="admin@acme.local"
      footer={
        <>
          <Link to="/">← Back to home</Link>
        </>
      }
      onSubmit={async (email, password) => {
        const data = await api.companyLogin(email, password);
        setSession({
          portal: 'company',
          token: data.token,
          user: data.user,
          company: {
            id: data.company.id,
            name: data.company.display_name || data.company.name,
            portal_onboarding_completed_at: data.company.portal_onboarding_completed_at,
          },
        });
        if (!data.company.portal_onboarding_completed_at) {
          navigate('/company/onboarding');
        } else {
          navigate('/company/dashboard');
        }
      }}
    />
  );
}
