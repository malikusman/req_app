import { Building2, Inbox, LayoutDashboard, MessageSquare, MessagesSquare, UserCircle } from 'lucide-react';
import type { SidebarItem } from '../../components/layout/Sidebar';

export const navItems: SidebarItem[] = [
  { to: '/reviewer/dashboard', label: 'Dashboard', icon: LayoutDashboard },
  { to: '/reviewer/profile', label: 'Profile', icon: UserCircle },
  { to: '/reviewer/followups', label: 'Follow-ups', icon: Inbox },
];

export function companyNavItems(companyId: number | string): SidebarItem[] {
  return [
    { to: `/reviewer/companies/${companyId}`, label: 'Company', icon: Building2 },
    {
      to: `/reviewer/companies/${companyId}/conversations`,
      label: 'Conversations',
      icon: MessagesSquare,
    },
    {
      to: `/reviewer/companies/${companyId}/chat`,
      label: 'Co-reviewer chat',
      icon: MessageSquare,
    },
  ];
}
