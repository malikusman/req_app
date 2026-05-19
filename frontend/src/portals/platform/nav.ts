import {
  Activity,
  BookOpen,
  Building2,
  LayoutDashboard,
  Package,
  ScrollText,
  Server,
  TestTube2,
  Users,
} from 'lucide-react';
import type { SidebarItem } from '../../components/layout/Sidebar';

export const navItems: SidebarItem[] = [
  { to: '/platform/dashboard', label: 'Dashboard', icon: LayoutDashboard },
  { to: '/platform/companies', label: 'Companies', icon: Building2 },
  { to: '/platform/reviewers', label: 'Reviewers', icon: Users },
  { to: '/platform/trials', label: 'Trials', icon: TestTube2 },
  { to: '/platform/playbooks', label: 'Playbooks', icon: BookOpen },
  { to: '/platform/solutions', label: 'Solutions', icon: Package },
  { to: '/platform/system', label: 'System', icon: Server },
  { to: '/platform/monitoring', label: 'Monitoring', icon: Activity },
  { to: '/platform/audit', label: 'Audit log', icon: ScrollText },
];
