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
  { to: '/company/intelligence', label: 'Intelligence', icon: Radio },
  { to: '/company/outreaches', label: 'Clarifications', icon: ShieldCheck },
  { to: '/company/reports', label: 'Reports', icon: FileBarChart },
  { to: '/company/settings', label: 'Settings', icon: Settings },
  { to: '/company/onboarding', label: 'Company profile', icon: Wrench },
];

/**
 * Compact primary company nav. Intelligence is a single hub; WhatsApp /
 * Conversations / Billing are reached from Dashboard tiles or Settings links.
 */
export function companyNavItems(): SidebarItem[] {
  return PRIMARY_NAV.map((item) => ({
    to: item.to,
    label: item.label,
    icon: item.icon,
  }));
}

export const navItems = companyNavItems();

/** Secondary destinations linked from Settings (and dashboard capture tiles). */
export const SETTINGS_SECONDARY_LINKS: {
  to: string;
  label: string;
  description: string;
  icon: LucideIcon;
}[] = [
  { to: '/company/billing', label: 'Billing', description: 'Trial usage and plan', icon: CreditCard },
  { to: '/company/media', label: 'WhatsApp media', description: 'Inbound discovery media', icon: Image },
  { to: '/company/conversations', label: 'Conversations', description: 'Employee discovery threads', icon: MessageSquare },
  { to: '/company/discovery-questions', label: 'Questions', description: 'Discovery question bank', icon: HelpCircle },
];
