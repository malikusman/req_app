import {
  CreditCard,
  FileBarChart,
  FileText,
  Image,
  LayoutDashboard,
  MessageSquare,
  Search,
  Settings,
  ShieldCheck,
  UserCircle,
  Users,
} from 'lucide-react';
import type { SidebarItem } from '../../components/layout/Sidebar';
import type { LucideIcon } from 'lucide-react';

export interface CompanyNavOpts {
  /** Company-profile completion percent; shows an amber badge while < 100. */
  profilePercent?: number;
  /** Latest report version; shows a `v{n}` badge when a report exists. */
  reportVersion?: number | null;
  /** Unanswered reviewer questions; shows an amber count badge when > 0. */
  reviewerQuestions?: number;
}

/**
 * Grouped company nav with live badges. Pass counts from the layout (which
 * already fetches the dashboard payload) to light up the badges.
 */
export function companyNavItems(opts: CompanyNavOpts = {}): SidebarItem[] {
  const { profilePercent, reportVersion, reviewerQuestions } = opts;

  const items: SidebarItem[] = [
    { to: '/company/dashboard', label: 'Home', icon: LayoutDashboard },

    { to: '/company/onboarding', label: 'Company profile', icon: UserCircle, section: 'Set up' },
    { to: '/company/documents', label: 'Documents', icon: FileText, section: 'Set up' },
    { to: '/company/employees', label: 'Your team', icon: Users, section: 'Set up' },

    { to: '/company/reports', label: 'Reports', icon: FileBarChart, section: 'Insights' },
    { to: '/company/intelligence', label: 'What we found', icon: Search, section: 'Insights' },
    { to: '/company/conversations', label: 'Conversations', icon: MessageSquare, section: 'Insights' },

    { to: '/company/outreaches', label: 'Reviewer questions', icon: ShieldCheck, section: 'Working with you' },
    { to: '/company/reviewers', label: 'Your reviewer', icon: UserCircle, section: 'Working with you' },

    { to: '/company/settings', label: 'Settings', icon: Settings },
  ];

  return items.map((item) => {
    if (item.to === '/company/onboarding' && profilePercent != null && profilePercent < 100) {
      return { ...item, badge: `${Math.round(profilePercent)}%`, badgeTone: 'attention' };
    }
    if (item.to === '/company/reports' && reportVersion != null) {
      return { ...item, badge: `v${reportVersion}` };
    }
    if (item.to === '/company/outreaches' && reviewerQuestions != null && reviewerQuestions > 0) {
      return { ...item, badge: String(reviewerQuestions), badgeTone: 'attention' };
    }
    return item;
  });
}

export const navItems = companyNavItems();

/** Secondary destinations linked from Settings. */
export const SETTINGS_SECONDARY_LINKS: {
  to: string;
  label: string;
  description: string;
  icon: LucideIcon;
}[] = [
  { to: '/company/billing', label: 'Billing', description: 'Trial usage and plan', icon: CreditCard },
  { to: '/company/media', label: 'WhatsApp media', description: 'Inbound discovery media', icon: Image },
];
