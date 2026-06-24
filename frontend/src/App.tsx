import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom';
import { AuthProvider, useAuth } from './lib/auth';
import { ToastProvider } from './components/ui/ToastProvider';
import { Toaster } from './components/shadcn/sonner';
import { MarketingPage } from './marketing/MarketingPage';
import { PlatformLogin } from './auth/PlatformLogin';
import { CompanyLogin } from './auth/CompanyLogin';
import { ReviewerLogin } from './auth/ReviewerLogin';
import { PlatformLayout } from './portals/platform/PlatformLayout';
import { PlatformDashboard } from './portals/platform/PlatformDashboard';
import { PlatformCompanies } from './portals/platform/PlatformCompanies';
import { PlatformCompanyDetail } from './portals/platform/PlatformCompanyDetail';
import { PlatformAuditLog } from './portals/platform/PlatformAuditLog';
import { PlatformTrials } from './portals/platform/PlatformTrials';
import { PlatformPlaybooks } from './portals/platform/PlatformPlaybooks';
import { PlatformSolutions } from './portals/platform/PlatformSolutions';
import { PlatformSystem } from './portals/platform/PlatformSystem';
import { PlatformMonitoringPage } from './portals/platform/PlatformMonitoring';
import { PlatformReviewers } from './portals/platform/PlatformReviewers';
import { CompanyLayout } from './portals/company/CompanyLayout';
import { CompanyDashboard } from './portals/company/CompanyDashboard';
import { CompanyOnboarding } from './portals/company/CompanyOnboarding';
import { CompanyEmployees } from './portals/company/CompanyEmployees';
import { CompanyConversations } from './portals/company/CompanyConversations';
import { CompanyConversationDetail } from './portals/company/CompanyConversationDetail';
import { CompanySignals } from './portals/company/CompanySignals';
import { CompanyPatterns } from './portals/company/CompanyPatterns';
import { CompanyDocuments } from './portals/company/CompanyDocuments';
import { CompanyMediaLibrary } from './portals/company/CompanyMediaLibrary';
import { CompanyTimeline } from './portals/company/CompanyTimeline';
import { CompanyDiscoveryQuestions } from './portals/company/CompanyDiscoveryQuestions';
import { CompanyRecommendations } from './portals/company/CompanyRecommendations';
import { CompanyReports } from './portals/company/CompanyReports';
import { CompanySettings } from './portals/company/CompanySettings';
import { CompanyBilling } from './portals/company/CompanyBilling';
import { ReviewerLayout } from './portals/reviewer/ReviewerLayout';
import { ReviewerDashboard } from './portals/reviewer/ReviewerDashboard';
import { ReviewerFollowups } from './portals/reviewer/ReviewerFollowups';
import { ReviewerCompanyOverview } from './portals/reviewer/ReviewerCompanyOverview';
import { ReviewerReportReview } from './portals/reviewer/ReviewerReportReview';
import { ReviewerConversations } from './portals/reviewer/ReviewerConversations';
import { ReviewerConversationDetail } from './portals/reviewer/ReviewerConversationDetail';
import { ReviewerChat } from './portals/reviewer/ReviewerChat';
import { ReviewerEmployeeFollowup } from './portals/reviewer/ReviewerEmployeeFollowup';
import { ReviewerProfile } from './portals/reviewer/ReviewerProfile';
import { DevUiShowcase } from './dev/DevUiShowcase';
import { DiscoverLanding } from './employee/DiscoverLanding';
import { DiscoverChat } from './employee/DiscoverChat';

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

function ReviewerGuard({ children }: { children: React.ReactNode }) {
  const { session } = useAuth();
  if (!session || session.portal !== 'reviewer') {
    return <Navigate to="/reviewer/login" replace />;
  }
  return <>{children}</>;
}

function HomeRoute() {
  const { session } = useAuth();
  if (session?.portal === 'platform') return <Navigate to="/platform/dashboard" replace />;
  if (session?.portal === 'reviewer') return <Navigate to="/reviewer/dashboard" replace />;
  if (session?.portal === 'company') {
    if (session.impersonating) return <Navigate to="/company/dashboard" replace />;
    const done = session.company.portal_onboarding_completed_at;
    return <Navigate to={done ? '/company/dashboard' : '/company/onboarding'} replace />;
  }
  return <MarketingPage />;
}

export default function App() {
  return (
    <AuthProvider>
      <ToastProvider>
        <Toaster richColors closeButton position="top-right" />
        <BrowserRouter>
          <Routes>
            <Route path="/" element={<HomeRoute />} />
            <Route path="/dev/ui" element={<DevUiShowcase />} />
            <Route path="/platform/login" element={<PlatformLogin />} />
            <Route path="/company/login" element={<CompanyLogin />} />
            <Route path="/reviewer/login" element={<ReviewerLogin />} />
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
              <Route path="companies/:id" element={<PlatformCompanyDetail />} />
              <Route path="audit" element={<PlatformAuditLog />} />
              <Route path="trials" element={<PlatformTrials />} />
              <Route path="playbooks" element={<PlatformPlaybooks />} />
              <Route path="solutions" element={<PlatformSolutions />} />
              <Route path="system" element={<PlatformSystem />} />
              <Route path="monitoring" element={<PlatformMonitoringPage />} />
              <Route path="reviewers" element={<PlatformReviewers />} />
            </Route>
            <Route
              path="/reviewer"
              element={
                <ReviewerGuard>
                  <ReviewerLayout />
                </ReviewerGuard>
              }
            >
              <Route index element={<Navigate to="dashboard" replace />} />
              <Route path="dashboard" element={<ReviewerDashboard />} />
              <Route path="profile" element={<ReviewerProfile />} />
              <Route path="followups" element={<ReviewerFollowups />} />
              <Route path="companies/:companyId" element={<ReviewerCompanyOverview />} />
              <Route path="companies/:companyId/reports/:reportId/review" element={<ReviewerReportReview />} />
              <Route path="companies/:companyId/conversations" element={<ReviewerConversations />} />
              <Route path="companies/:companyId/conversations/:conversationId" element={<ReviewerConversationDetail />} />
              <Route path="companies/:companyId/chat" element={<ReviewerChat />} />
              <Route path="companies/:companyId/employees/:employeeId/followup" element={<ReviewerEmployeeFollowup />} />
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
              <Route path="conversations" element={<CompanyConversations />} />
              <Route path="conversations/:id" element={<CompanyConversationDetail />} />
              <Route path="intelligence/signals" element={<CompanySignals />} />
              <Route path="intelligence/patterns" element={<CompanyPatterns />} />
              <Route path="documents" element={<CompanyDocuments />} />
              <Route path="media" element={<CompanyMediaLibrary />} />
              <Route path="intelligence/timeline" element={<CompanyTimeline />} />
              <Route path="discovery-questions" element={<CompanyDiscoveryQuestions />} />
              <Route path="recommendations" element={<CompanyRecommendations />} />
              <Route path="reports" element={<CompanyReports />} />
              <Route path="settings" element={<CompanySettings />} />
              <Route path="billing" element={<CompanyBilling />} />
            </Route>
            <Route path="/discover/:token" element={<DiscoverLanding />} />
            <Route path="/discover/:token/chat" element={<DiscoverChat />} />
            <Route path="*" element={<Navigate to="/" replace />} />
          </Routes>
        </BrowserRouter>
      </ToastProvider>
    </AuthProvider>
  );
}
