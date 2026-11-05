import {
  CreditCard,
  FileBarChart,
  FileText,
  LayoutDashboard,
  MessagesSquare,
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
  profileSubmitted?: boolean;
  /** Latest report version; shows a `v{n}` badge when a report exists. */
  reportVersion?: number | null;
  /** Unanswered consultant questions; shows an amber count badge when > 0. */
  consultantQuestions?: number;
  /** The key user's conversation with leadership: shown once it exists; 'To do' until finished. */
  leadership?: { finished: boolean } | null;
}

/**
 * Grouped company nav with live badges. Pass counts from the layout (which
 * already fetches the dashboard payload) to light up the badges.
 */
export function companyNavItems(opts: CompanyNavOpts = {}): SidebarItem[] {
  const { profileSubmitted, reportVersion, consultantQuestions, leadership } = opts;

  const items: SidebarItem[] = [
    { to: '/company/dashboard', label: 'Home', icon: LayoutDashboard },

    { to: '/company/onboarding', label: 'Company profile', icon: UserCircle, section: 'Set up' },
    ...(leadership
      ? [{ to: '/company/leadership', label: 'Leadership conversation', icon: MessagesSquare, section: 'Set up' }]
      : []),
    { to: '/company/documents', label: 'Documents', icon: FileText, section: 'Set up' },
    { to: '/company/employees', label: 'Your team', icon: Users, section: 'Set up' },

    { to: '/company/reports', label: 'Reports', icon: FileBarChart, section: 'Insights' },
    { to: '/company/intelligence', label: 'What we found', icon: Search, section: 'Insights' },

    { to: '/company/outreaches', label: 'Consultant questions', icon: ShieldCheck, section: 'Working with you' },
    { to: '/company/consultants', label: 'Your consultant', icon: UserCircle, section: 'Working with you' },

    { to: '/company/settings', label: 'Settings', icon: Settings },
  ];

  return items.map((item) => {
    if (item.to === '/company/onboarding' && profileSubmitted === false) {
      return { ...item, badge: 'To do', badgeTone: 'attention' };
    }
    if (item.to === '/company/leadership' && leadership && !leadership.finished) {
      return { ...item, badge: 'To do', badgeTone: 'attention' };
    }
    if (item.to === '/company/reports' && reportVersion != null) {
      return { ...item, badge: `v${reportVersion}` };
    }
    if (item.to === '/company/outreaches' && consultantQuestions != null && consultantQuestions > 0) {
      return { ...item, badge: String(consultantQuestions), badgeTone: 'attention' };
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
];
