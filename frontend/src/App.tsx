import { BrowserRouter, Navigate, Route, Routes, useLocation } from 'react-router-dom';
import { AuthProvider, useAuth } from './lib/auth';
import { ToastProvider } from './components/ui/ToastProvider';
import { Toaster } from './components/shadcn/sonner';
import { MarketingPage } from './marketing/MarketingPage';
import { PrivacyPage } from './marketing/PrivacyPage';
import { PlatformLogin } from './auth/PlatformLogin';
import { CompanyLogin } from './auth/CompanyLogin';
import { ConsultantLogin } from './auth/ConsultantLogin';
import { CompanySignupPage } from './auth/CompanySignupPage';
import { ConsultantApplyPage } from './auth/ConsultantApplyPage';
import { ForgotPasswordPage } from './auth/ForgotPasswordPage';
import { SetPasswordPage } from './auth/SetPasswordPage';
import { PlatformLayout } from './portals/platform/PlatformLayout';
import { PlatformDashboard } from './portals/platform/PlatformDashboard';
import { PlatformCompanies } from './portals/platform/PlatformCompanies';
import { PlatformCompanyDetail } from './portals/platform/PlatformCompanyDetail';
import { PlatformPlaybooks } from './portals/platform/PlatformPlaybooks';
import { PlatformSolutions } from './portals/platform/PlatformSolutions';
import { PlatformOperations } from './portals/platform/PlatformOperations';
import { PlatformConsultants } from './portals/platform/PlatformConsultants';
import { PlatformConsultantDetail } from './portals/platform/PlatformConsultantDetail';
import { PlatformRegistrations } from './portals/platform/PlatformRegistrations';
import { PlatformApprovals } from './portals/platform/PlatformApprovals';
import { CompanyLayout } from './portals/company/CompanyLayout';
import { CompanyDashboard } from './portals/company/CompanyDashboard';
import { CompanyOnboarding } from './portals/company/CompanyOnboarding';
import { CompanyEmployees } from './portals/company/CompanyEmployees';
import { CompanyConversations } from './portals/company/CompanyConversations';
import { CompanyConversationDetail } from './portals/company/CompanyConversationDetail';
import { CompanyIntelligence } from './portals/company/CompanyIntelligence';
import { CompanyDocuments } from './portals/company/CompanyDocuments';
import { CompanyKnowledge } from './portals/company/CompanyKnowledge';
import { ConsultantDocuments } from './portals/consultant/ConsultantDocuments';
import { ConsultantDocumentAnalysis } from './portals/consultant/ConsultantDocumentAnalysis';
import { CompanyMediaLibrary } from './portals/company/CompanyMediaLibrary';
import { CompanyDiscoveryQuestions } from './portals/company/CompanyDiscoveryQuestions';
import { CompanyReports } from './portals/company/CompanyReports';
import { CompanyConsultantsPage } from './portals/company/CompanyConsultantsPage';
import { CompanySettings } from './portals/company/CompanySettings';
import { CompanyBilling } from './portals/company/CompanyBilling';
import { ConsultantLayout } from './portals/consultant/ConsultantLayout';
import { ConsultantDashboard } from './portals/consultant/ConsultantDashboard';
import { ConsultantFollowups } from './portals/consultant/ConsultantFollowups';
import { ConsultantCompanyOverview } from './portals/consultant/ConsultantCompanyOverview';
import { ConsultantReportWorkspace } from './portals/consultant/workspace/ConsultantReportWorkspace';
import { ConsultantConversations } from './portals/consultant/ConsultantConversations';
import { ConsultantConversationDetail } from './portals/consultant/ConsultantConversationDetail';
import { ConsultantEmployeeFollowup } from './portals/consultant/ConsultantEmployeeFollowup';
import { ConsultantProfile } from './portals/consultant/ConsultantProfile';
import { DevUiShowcase } from './dev/DevUiShowcase';
import { CompanyOutreaches } from './portals/company/CompanyOutreaches';
import { PlatformCatalogCandidates } from './portals/platform/PlatformCatalogCandidates';
import { PlatformCatalogSources } from './portals/platform/PlatformCatalogSources';
import { OutreachReplyPage } from './portals/public/OutreachReplyPage';
import { ConsultantCatalog } from './portals/consultant/ConsultantCatalog';
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

function ConsultantGuard({ children }: { children: React.ReactNode }) {
  const { session } = useAuth();
  if (!session || session.portal !== 'consultant') {
    return <Navigate to="/consultant/login" replace />;
  }
  return <>{children}</>;
}

function HomeRoute() {
  const { session } = useAuth();
  if (session?.portal === 'platform') return <Navigate to="/platform/dashboard" replace />;
  if (session?.portal === 'consultant') return <Navigate to="/consultant/dashboard" replace />;
  if (session?.portal === 'company') {
    if (session.impersonating) return <Navigate to="/company/dashboard" replace />;
    const done = session.company.portal_onboarding_completed_at;
    return <Navigate to={done ? '/company/dashboard' : '/company/onboarding'} replace />;
  }
  return <MarketingPage />;
}

/**
 * Redirects the pre-rename /reviewer/* paths onto /consultant/*, keeping the
 * subpath and query string so a deep link still lands where it meant to.
 */
function LegacyReviewerRedirect() {
  const location = useLocation();
  const target = location.pathname.replace(/^\/reviewer/, '/consultant');
  return <Navigate to={`${target}${location.search}${location.hash}`} replace />;
}

export default function App() {
  return (
    <AuthProvider>
      <ToastProvider>
        <Toaster richColors closeButton position="top-right" />
        <BrowserRouter>
          <Routes>
            <Route path="/" element={<HomeRoute />} />
            <Route path="/privacy" element={<PrivacyPage />} />
            <Route path="/dev/ui" element={<DevUiShowcase />} />
            <Route path="/platform/login" element={<PlatformLogin />} />
            <Route path="/company/login" element={<CompanyLogin />} />
            <Route path="/company/signup" element={<CompanySignupPage />} />
            <Route path="/consultant/login" element={<ConsultantLogin />} />
            {/* Pre-rename paths. Approval emails, bookmarks and shared links point
                at /reviewer/*, so they redirect rather than 404. */}
            <Route path="/reviewer/*" element={<LegacyReviewerRedirect />} />
            <Route path="/consultant/apply" element={<ConsultantApplyPage />} />
            <Route path="/auth/forgot-password" element={<ForgotPasswordPage />} />
            <Route path="/auth/set-password" element={<SetPasswordPage />} />
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
              <Route path="approvals" element={<PlatformApprovals />} />
              <Route path="registrations" element={<PlatformRegistrations />} />
              <Route path="companies" element={<PlatformCompanies />} />
              <Route path="companies/:id" element={<PlatformCompanyDetail />} />
              <Route path="playbooks" element={<PlatformPlaybooks />} />
              <Route path="solutions" element={<PlatformSolutions />} />
              <Route path="catalog/sources" element={<PlatformCatalogSources />} />
              <Route path="catalog/candidates" element={<PlatformCatalogCandidates />} />
              <Route path="operations" element={<PlatformOperations />} />
              {/* Consolidated into Operations tabs; keep old paths as redirects */}
              <Route path="system" element={<Navigate to="/platform/operations?tab=system" replace />} />
              <Route path="monitoring" element={<Navigate to="/platform/operations?tab=monitoring" replace />} />
              <Route path="trials" element={<Navigate to="/platform/operations?tab=trials" replace />} />
              <Route path="audit" element={<Navigate to="/platform/operations?tab=audit" replace />} />
              <Route path="consultants" element={<PlatformConsultants />} />
              <Route path="consultants/:id" element={<PlatformConsultantDetail />} />
            </Route>
            <Route
              path="/consultant"
              element={
                <ConsultantGuard>
                  <ConsultantLayout />
                </ConsultantGuard>
              }
            >
              <Route index element={<Navigate to="dashboard" replace />} />
              <Route path="dashboard" element={<ConsultantDashboard />} />
              <Route path="profile" element={<ConsultantProfile />} />
              <Route path="followups" element={<Navigate to="/consultant/inbox" replace />} />
              <Route path="inbox" element={<ConsultantFollowups />} />
              <Route path="companies/:companyId" element={<ConsultantCompanyOverview />} />
              <Route path="companies/:companyId/reports/:reportId/review" element={<ConsultantReportWorkspace />} />
              <Route path="companies/:companyId/conversations" element={<ConsultantConversations />} />
              <Route path="companies/:companyId/conversations/:conversationId" element={<ConsultantConversationDetail />} />
              <Route path="companies/:companyId/employees/:employeeId/followup" element={<ConsultantEmployeeFollowup />} />
              <Route path="companies/:companyId/documents" element={<ConsultantDocuments />} />
              <Route path="companies/:companyId/analysis" element={<ConsultantDocumentAnalysis />} />
              <Route path="companies/:companyId/catalog" element={<ConsultantCatalog />} />
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
              <Route path="intelligence" element={<CompanyIntelligence />} />
              <Route path="intelligence/signals" element={<Navigate to="/company/intelligence#signals" replace />} />
              <Route path="intelligence/patterns" element={<Navigate to="/company/intelligence#patterns" replace />} />
              <Route path="intelligence/timeline" element={<Navigate to="/company/intelligence#timeline" replace />} />
              <Route path="documents" element={<CompanyDocuments />} />
              <Route path="knowledge" element={<CompanyKnowledge />} />
              <Route path="outreaches" element={<CompanyOutreaches />} />
              <Route path="media" element={<CompanyMediaLibrary />} />
              <Route path="discovery-questions" element={<CompanyDiscoveryQuestions />} />
              <Route path="recommendations" element={<Navigate to="/company/intelligence#recommendations" replace />} />
              <Route path="reports" element={<CompanyReports />} />
              <Route path="consultants" element={<CompanyConsultantsPage />} />
              <Route path="settings" element={<CompanySettings />} />
              <Route path="billing" element={<CompanyBilling />} />
            </Route>
            <Route path="/discover/:token" element={<DiscoverLanding />} />
            <Route path="/discover/:token/chat" element={<DiscoverChat />} />
            <Route path="/outreach/reply/:token" element={<OutreachReplyPage />} />
            <Route path="*" element={<Navigate to="/" replace />} />
          </Routes>
        </BrowserRouter>
      </ToastProvider>
    </AuthProvider>
  );
}
