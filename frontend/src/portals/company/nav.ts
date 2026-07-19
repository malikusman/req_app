import {
  Clock,
  CreditCard,
  FileBarChart,
  FileText,
  HelpCircle,
  Image,
  LayoutDashboard,
  Lightbulb,
  MessageSquare,
  Radio,
  Settings,
  Shapes,
  ShieldCheck,
  CalendarClock,
  Users,
  Wrench,
} from 'lucide-react';
import type { SidebarItem } from '../../components/layout/Sidebar';

/** Interview-centric destinations demoted (or badged) during docs-first phase. */
const INTERVIEW_ONLY = new Set([
  '/company/conversations',
  '/company/outreaches',
  '/company/meeting-requests',
  '/company/media',
  '/company/discovery-questions',
]);

const SECTIONS = {
  overview: 'Overview',
  baseline: 'Baseline',
  people: 'People',
  intelligence: 'Intelligence',
  delivery: 'Delivery',
  admin: 'Admin',
} as const;

type NavDef = SidebarItem & { section: string; interviewOnly?: boolean };

const BASE_NAV: NavDef[] = [
  { to: '/company/dashboard', label: 'Dashboard', icon: LayoutDashboard, section: SECTIONS.overview },
  { to: '/company/documents', label: 'Documents', icon: FileText, section: SECTIONS.baseline },
  { to: '/company/employees', label: 'Employees', icon: Users, section: SECTIONS.people },
  { to: '/company/conversations', label: 'Conversations', icon: MessageSquare, section: SECTIONS.people, interviewOnly: true },
  { to: '/company/outreaches', label: 'Clarifications', icon: ShieldCheck, section: SECTIONS.people, interviewOnly: true },
  { to: '/company/meeting-requests', label: 'Meetings', icon: CalendarClock, section: SECTIONS.people, interviewOnly: true },
  { to: '/company/media', label: 'WhatsApp media', icon: Image, section: SECTIONS.people, interviewOnly: true },
  { to: '/company/intelligence/signals', label: 'Signals', icon: Radio, section: SECTIONS.intelligence },
  { to: '/company/intelligence/patterns', label: 'Patterns', icon: Shapes, section: SECTIONS.intelligence },
  { to: '/company/intelligence/timeline', label: 'Timeline', icon: Clock, section: SECTIONS.intelligence },
  { to: '/company/recommendations', label: 'Recommendations', icon: Lightbulb, section: SECTIONS.intelligence },
  { to: '/company/reports', label: 'Reports', icon: FileBarChart, section: SECTIONS.delivery },
  { to: '/company/billing', label: 'Billing', icon: CreditCard, section: SECTIONS.admin },
  { to: '/company/discovery-questions', label: 'Questions', icon: HelpCircle, section: SECTIONS.admin, interviewOnly: true },
  { to: '/company/settings', label: 'Settings', icon: Settings, section: SECTIONS.admin },
  { to: '/company/onboarding', label: 'Setup', icon: Wrench, section: SECTIONS.admin },
];

/**
 * Grouped company nav. In docs-first phase, Documents stays early and interview-only
 * items are badged “Later” so admins know they apply after invites.
 */
export function companyNavItems(opts?: { docsFirstPhase?: boolean; onboardingComplete?: boolean }): SidebarItem[] {
  const docsFirst = Boolean(opts?.docsFirstPhase);
  const hideSetup = Boolean(opts?.onboardingComplete);

  return BASE_NAV.filter((item) => !(hideSetup && item.to === '/company/onboarding')).map((item) => {
    const next: SidebarItem = {
      to: item.to,
      label: item.label,
      icon: item.icon,
      section: item.section,
    };
    if (docsFirst && (item.interviewOnly || INTERVIEW_ONLY.has(item.to))) {
      next.badge = 'Later';
    }
    return next;
  });
}

export const navItems = companyNavItems();
