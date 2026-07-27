import {
  BookOpen,
  CreditCard,
  FileBarChart,
  FileText,
  HelpCircle,
  Image,
  LayoutDashboard,
  MessageSquare,
  Radio,
  Settings,
  ShieldCheck,
  UserCircle,
  Users,
  Wrench,
} from 'lucide-react';
import type { SidebarItem } from '../../components/layout/Sidebar';
import type { LucideIcon } from 'lucide-react';

type NavDef = SidebarItem;

const PRIMARY_NAV: NavDef[] = [
  { to: '/company/dashboard', label: 'Dashboard', icon: LayoutDashboard },
  { to: '/company/documents', label: 'Documents', icon: FileText },
  { to: '/company/knowledge', label: 'Knowledge', icon: BookOpen },
  { to: '/company/employees', label: 'Employees', icon: Users },
  { to: '/company/conversations', label: 'Conversations', icon: MessageSquare },
  { to: '/company/discovery-questions', label: 'Discovery questions', icon: HelpCircle },
  { to: '/company/intelligence', label: 'Intelligence', icon: Radio },
  { to: '/company/outreaches', label: 'Reviewer questions', icon: ShieldCheck },
  { to: '/company/reviewers', label: 'Reviewers', icon: UserCircle },
  { to: '/company/reports', label: 'Reports', icon: FileBarChart },
  { to: '/company/onboarding', label: 'Profile', icon: Wrench },
  { to: '/company/settings', label: 'Settings', icon: Settings },
];

/**
 * Primary company nav. Billing / WhatsApp media stay under Settings.
 */
export function companyNavItems(): SidebarItem[] {
  return PRIMARY_NAV.map((item) => ({
    to: item.to,
    label: item.label,
    icon: item.icon,
  }));
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
