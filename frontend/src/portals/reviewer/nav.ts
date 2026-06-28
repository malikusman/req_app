import { Inbox, LayoutDashboard, UserCircle } from 'lucide-react';
import type { SidebarItem } from '../../components/layout/Sidebar';

export const navItems: SidebarItem[] = [
  { to: '/reviewer/dashboard', label: 'Dashboard', icon: LayoutDashboard },
  { to: '/reviewer/profile', label: 'Profile', icon: UserCircle },
  { to: '/reviewer/inbox', label: 'Inbox', icon: Inbox },
];
