import { useNavigate, Link } from 'react-router-dom';
import { api } from '../lib/api';
import { useAuth } from '../lib/auth';
import { LoginForm } from './LoginForm';

export function ConsultantLogin() {
  const { setSession } = useAuth();
  const navigate = useNavigate();

  return (
    <LoginForm
      portal="consultant"
      portalName="Worktruth — Consultant"
      tagline="Review discovery reports and coordinate expert analysis."
      defaultEmail="consultant@reqapp.local"
      forgotPasswordTo="/auth/forgot-password?portal=consultant"
      footer={
        <>
          <Link to="/consultant/apply">Become a consultant</Link>
          {' · '}
          <Link to="/">Back to home</Link>
        </>
      }
      onSubmit={async (email, password) => {
        const data = await api.consultantLogin(email, password);
        setSession({ portal: 'consultant', token: data.token, user: data.user });
        navigate('/consultant/dashboard');
      }}
    />
  );
}
