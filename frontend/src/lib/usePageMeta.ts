import { useEffect } from 'react';
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
  '/reviewer/profile': 'Profile',
  '/reviewer/inbox': 'Inbox',
  '/reviewer/followups': 'Inbox',
};

function resolveTitle(pathname: string, fallback: string): string {
  const exact = titles[pathname];
  if (exact) return exact;

  if (pathname.includes('/reviewer/companies/') && pathname.includes('/reports/') && pathname.endsWith('/review')) {
    return 'Report review';
  }
  if (pathname.match(/\/reviewer\/companies\/\d+\/employees\/\d+\/followup/)) {
    return 'Employee follow-up';
  }
  if (pathname.includes('/companies/') && pathname.includes('/conversations/')) {
    return 'Conversation';
  }
  if (pathname.includes('/companies/') && pathname.includes('/conversations')) {
    return 'Conversations';
  }
  if (pathname.includes('/companies/') && pathname.includes('/chat')) {
    return 'Co-reviewer chat';
  }
  if (pathname.match(/\/reviewer\/companies\/\d+$/)) {
    return 'Company overview';
  }
  if (pathname.match(/\/platform\/companies\/\d+/)) {
    return 'Company detail';
  }

  return fallback;
}

export function usePageMeta(fallback = 'Worktruth') {
  const { pathname } = useLocation();
  const title = resolveTitle(pathname, fallback);

  useEffect(() => {
    document.title = title === 'Worktruth' ? 'Worktruth' : `${title} · Worktruth`;
  }, [title]);

  return { title };
}
