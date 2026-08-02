import {
  BookOpen,
  Building2,
  LayoutDashboard,
  Package,
  Inbox,
  Rss,
  SlidersHorizontal,
  UserPlus,
  Users,
} from 'lucide-react';
import type { SidebarItem } from '../../components/layout/Sidebar';

export const navItems: SidebarItem[] = [
  { to: '/platform/dashboard', label: 'Dashboard', icon: LayoutDashboard },
  { to: '/platform/registrations', label: 'Registrations', icon: UserPlus },
  { to: '/platform/companies', label: 'Companies', icon: Building2 },
  { to: '/platform/reviewers', label: 'Reviewers', icon: Users },
  { to: '/platform/playbooks', label: 'Playbooks', icon: BookOpen },
  { to: '/platform/solutions', label: 'Solutions', icon: Package },
  { to: '/platform/catalog/sources', label: 'Sources', icon: Rss },
  { to: '/platform/catalog/candidates', label: 'Candidates', icon: Inbox },
  // System, Monitoring, Trials, Audit consolidated into Operations tabs.
  { to: '/platform/operations', label: 'Operations', icon: SlidersHorizontal },
];
