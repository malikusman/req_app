import { useLocation } from 'react-router-dom';

const titles: Record<string, string> = {
  '/platform/dashboard': 'Dashboard',
  '/platform/companies': 'Companies',
  '/platform/reviewers': 'Reviewers',
  '/platform/trials': 'Trials',
  '/platform/playbooks': 'Playbooks',
  '/platform/solutions': 'Solutions',
  '/platform/system': 'System health',
  '/platform/monitoring': 'Monitoring',
  '/platform/audit': 'Audit log',
  '/company/dashboard': 'Dashboard',
  '/company/employees': 'Employees',
  '/company/conversations': 'Conversations',
  '/company/intelligence/signals': 'Signals',
  '/company/intelligence/patterns': 'Patterns',
  '/company/intelligence/timeline': 'Timeline',
  '/company/documents': 'Documents',
  '/company/recommendations': 'Recommendations',
  '/company/reports': 'Reports',
  '/company/billing': 'Billing',
  '/company/discovery-questions': 'Discovery questions',
  '/company/settings': 'Settings',
  '/company/onboarding': 'Setup',
  '/reviewer/dashboard': 'Dashboard',
  '/reviewer/followups': 'Follow-ups',
};

export function usePageMeta(fallback = 'Req') {
  const { pathname } = useLocation();
  const exact = titles[pathname];
  if (exact) return { title: exact };

  if (pathname.includes('/review/companies/') && pathname.endsWith('/review')) {
    return { title: 'Report review' };
  }
  if (pathname.includes('/companies/') && pathname.includes('/conversations/')) {
    return { title: 'Conversation' };
  }
  if (pathname.includes('/companies/') && pathname.includes('/conversations')) {
    return { title: 'Conversations' };
  }
  if (pathname.includes('/companies/') && pathname.includes('/chat')) {
    return { title: 'Co-reviewer chat' };
  }
  if (pathname.match(/\/reviewer\/companies\/\d+$/)) {
    return { title: 'Company overview' };
  }
  if (pathname.match(/\/platform\/companies\/\d+/)) {
    return { title: 'Company detail' };
  }

  return { title: fallback };
}
