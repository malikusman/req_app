import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom';
import { AuthProvider, useAuth } from './lib/auth';
import { PlatformLogin } from './auth/PlatformLogin';
import { CompanyLogin } from './auth/CompanyLogin';
import { PlatformLayout } from './portals/platform/PlatformLayout';
import { PlatformDashboard } from './portals/platform/PlatformDashboard';
import { PlatformCompanies } from './portals/platform/PlatformCompanies';
import { PlatformTrials } from './portals/platform/PlatformTrials';
import { PlatformPlaybooks } from './portals/platform/PlatformPlaybooks';
import { CompanyLayout } from './portals/company/CompanyLayout';
import { CompanyDashboard } from './portals/company/CompanyDashboard';
import { CompanyOnboarding } from './portals/company/CompanyOnboarding';
import { CompanyEmployees } from './portals/company/CompanyEmployees';
import { CompanyDocuments } from './portals/company/CompanyDocuments';
import { CompanyTimeline } from './portals/company/CompanyTimeline';
import { CompanyDiscoveryQuestions } from './portals/company/CompanyDiscoveryQuestions';
import { CompanyRecommendations } from './portals/company/CompanyRecommendations';
import { PlatformSolutions } from './portals/platform/PlatformSolutions';
import { PlatformSystem } from './portals/platform/PlatformSystem';
import { CompanyReports } from './portals/company/CompanyReports';
import { CompanySettings } from './portals/company/CompanySettings';
import { CompanyBilling } from './portals/company/CompanyBilling';
import { PlatformMonitoringPage } from './portals/platform/PlatformMonitoring';

function PlatformGuard({ children }: { children: React.ReactNode }) {
  const { session } = useAuth();
  if (!session || session.portal !== 'platform') {
    return <Navigate to="/platform/login" replace />;
  }
  return <>{children}</>;
}

function CompanyGuard({ children }: { children: React.ReactNode }) {
  const { session } = useAuth();
  if (!session || session.portal !== 'company') {
    return <Navigate to="/company/login" replace />;
  }
  return <>{children}</>;
}

function HomeRedirect() {
  const { session } = useAuth();
  if (session?.portal === 'platform') return <Navigate to="/platform/dashboard" replace />;
  if (session?.portal === 'company') {
    if (session.impersonating) return <Navigate to="/company/dashboard" replace />;
    const done = session.company.portal_onboarding_completed_at;
    return <Navigate to={done ? '/company/dashboard' : '/company/onboarding'} replace />;
  }
  return (
    <div style={{ minHeight: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '1rem' }}>
      <a href="/platform/login" className="btn btn-primary">
        Platform login
      </a>
      <a href="/company/login" className="btn btn-secondary">
        Company login
      </a>
    </div>
  );
}

export default function App() {
  return (
    <AuthProvider>
      <BrowserRouter>
        <Routes>
          <Route path="/" element={<HomeRedirect />} />
          <Route path="/platform/login" element={<PlatformLogin />} />
          <Route path="/company/login" element={<CompanyLogin />} />
          <Route
            path="/platform"
            element={
              <PlatformGuard>
                <PlatformLayout />
              </PlatformGuard>
            }
          >
            <Route index element={<Navigate to="dashboard" replace />} />
            <Route path="dashboard" element={<PlatformDashboard />} />
            <Route path="companies" element={<PlatformCompanies />} />
            <Route path="trials" element={<PlatformTrials />} />
            <Route path="playbooks" element={<PlatformPlaybooks />} />
            <Route path="solutions" element={<PlatformSolutions />} />
            <Route path="system" element={<PlatformSystem />} />
            <Route path="monitoring" element={<PlatformMonitoringPage />} />
          </Route>
          <Route
            path="/company"
            element={
              <CompanyGuard>
                <CompanyLayout />
              </CompanyGuard>
            }
          >
            <Route index element={<Navigate to="dashboard" replace />} />
            <Route path="dashboard" element={<CompanyDashboard />} />
            <Route path="onboarding" element={<CompanyOnboarding />} />
            <Route path="employees" element={<CompanyEmployees />} />
            <Route path="documents" element={<CompanyDocuments />} />
            <Route path="intelligence/timeline" element={<CompanyTimeline />} />
            <Route path="discovery-questions" element={<CompanyDiscoveryQuestions />} />
            <Route path="recommendations" element={<CompanyRecommendations />} />
            <Route path="reports" element={<CompanyReports />} />
            <Route path="settings" element={<CompanySettings />} />
            <Route path="billing" element={<CompanyBilling />} />
          </Route>
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </BrowserRouter>
    </AuthProvider>
  );
}
