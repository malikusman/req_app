import { useNavigate, Link } from 'react-router-dom';
import { api } from '../lib/api';
import { useAuth } from '../lib/auth';
import { LoginForm } from './LoginForm';

export function ReviewerLogin() {
  const { setSession } = useAuth();
  const navigate = useNavigate();

  return (
    <LoginForm
      portal="reviewer"
      portalName="Worktruth — Reviewer"
      tagline="Review discovery reports and coordinate expert analysis."
      defaultEmail="reviewer@reqapp.local"
      footer={<Link to="/">← Back to home</Link>}
      onSubmit={async (email, password) => {
        const data = await api.reviewerLogin(email, password);
        setSession({ portal: 'reviewer', token: data.token, user: data.user });
        navigate('/reviewer/dashboard');
      }}
    />
  );
}
