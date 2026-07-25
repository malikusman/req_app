import {
  CalendarClock,
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

type NavDef = SidebarItem & { hideWhenOnboarded?: boolean };

const PRIMARY_NAV: NavDef[] = [
  { to: '/company/dashboard', label: 'Dashboard', icon: LayoutDashboard },
  { to: '/company/documents', label: 'Documents', icon: FileText },
  { to: '/company/employees', label: 'Employees', icon: Users },
  { to: '/company/intelligence', label: 'Intelligence', icon: Radio },
  { to: '/company/outreaches', label: 'Clarifications', icon: ShieldCheck },
  { to: '/company/reports', label: 'Reports', icon: FileBarChart },
  { to: '/company/settings', label: 'Settings', icon: Settings },
  { to: '/company/onboarding', label: 'Company profile', icon: Wrench, hideWhenOnboarded: true },
];

/**
 * Compact primary company nav. Intelligence is a single hub; Meetings / WhatsApp /
 * Conversations / Billing are reached from Dashboard tiles or Settings links.
 * When impersonating, keep Company profile visible so platform support can open the questionnaire.
 */
export function companyNavItems(opts?: {
  docsFirstPhase?: boolean;
  onboardingComplete?: boolean;
  impersonating?: boolean;
}): SidebarItem[] {
  const hideSetup = Boolean(opts?.onboardingComplete) && !opts?.impersonating;

  return PRIMARY_NAV.filter((item) => !(hideSetup && item.hideWhenOnboarded)).map((item) => {
    const next: SidebarItem = {
      to: item.to,
      label: item.to === '/company/onboarding' ? 'Company profile' : item.label,
      icon: item.icon,
    };
    return next;
  });
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
  { to: '/company/meeting-requests', label: 'Meetings', description: 'Reviewer meeting requests', icon: CalendarClock },
  { to: '/company/media', label: 'WhatsApp media', description: 'Inbound discovery media', icon: Image },
  { to: '/company/conversations', label: 'Conversations', description: 'Employee discovery threads', icon: MessageSquare },
  { to: '/company/discovery-questions', label: 'Questions', description: 'Discovery question bank', icon: HelpCircle },
];
