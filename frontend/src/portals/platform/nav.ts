import {
  BookOpen,
  Building2,
  FileCheck2,
  LayoutDashboard,
  Package,
  Inbox,
  Rss,
  SlidersHorizontal,
  UserPlus,
  Users,
} from 'lucide-react';
import type { SidebarItem } from '../../components/layout/Sidebar';

export interface PlatformNavCounts {
  /** Pending company signups + consultant applications awaiting approval. */
  registrations?: number;
  /** Catalog candidates awaiting review. */
  candidates?: number;
  /** Reports sitting on the approval gate, awaiting the operator. */
  approvals?: number;
}

/**
 * Grouped platform nav with live attention badges. Pass counts from the layout
 * (which fetches the lightest pending-work endpoints) to light up the badges.
 * Mirrors companyNavItems / consultantNavItems.
 */
export function platformNavItems(counts: PlatformNavCounts = {}): SidebarItem[] {
  const { registrations, candidates, approvals } = counts;

  const items: SidebarItem[] = [
    { to: '/platform/dashboard', label: 'Dashboard', icon: LayoutDashboard },

    { to: '/platform/approvals', label: 'Approvals', icon: FileCheck2, section: 'Operate' },
    { to: '/platform/registrations', label: 'Registrations', icon: UserPlus, section: 'Operate' },
    { to: '/platform/companies', label: 'Companies', icon: Building2, section: 'Operate' },
    { to: '/platform/consultants', label: 'Consultants', icon: Users, section: 'Operate' },

    { to: '/platform/playbooks', label: 'Playbooks', icon: BookOpen, section: 'Catalog' },
    { to: '/platform/solutions', label: 'Solutions', icon: Package, section: 'Catalog' },
    { to: '/platform/catalog/sources', label: 'Sources', icon: Rss, section: 'Catalog' },
    { to: '/platform/catalog/candidates', label: 'Candidates', icon: Inbox, section: 'Catalog' },

    // System, Monitoring, Trials, Audit consolidated into Operations tabs.
    { to: '/platform/operations', label: 'Operations', icon: SlidersHorizontal },
  ];

  return items.map((item) => {
    if (item.to === '/platform/approvals' && approvals != null && approvals > 0) {
      return { ...item, badge: String(approvals), badgeTone: 'attention' };
    }
    if (item.to === '/platform/registrations' && registrations != null && registrations > 0) {
      return { ...item, badge: String(registrations), badgeTone: 'attention' };
    }
    if (item.to === '/platform/catalog/candidates' && candidates != null && candidates > 0) {
      return { ...item, badge: String(candidates), badgeTone: 'attention' };
    }
    return item;
  });
}

/** Static base nav (no counts) — safe fallback if the layout fetch fails. */
export const navItems: SidebarItem[] = platformNavItems();
