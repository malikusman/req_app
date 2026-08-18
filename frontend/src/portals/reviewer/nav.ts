import { Building2, Home, Inbox, UserCircle } from 'lucide-react';
import type { SidebarItem } from '../../components/layout/Sidebar';
import type { ReviewerCompanyDetail, ReviewerDashboardPayload } from '../../lib/api';

/** A company's report review is waiting on this reviewer. */
export function isReviewPending(c: ReviewerCompanyDetail): boolean {
  if (!c.latest_report) return false;
  if (c.review_pending === true) return true;
  const status = c.my_review_status;
  return !status || status === 'pending' || status === 'needs_info';
}

/**
 * Grouped reviewer nav. The "Your companies" section is the point of the
 * redesign: it lists one item per assignment (fed by the dashboard payload the
 * layout already fetches), each badged when its review is waiting on you.
 */
export function reviewerNavItems(payload?: ReviewerDashboardPayload | null): SidebarItem[] {
  const items: SidebarItem[] = [{ to: '/reviewer/dashboard', label: 'Home', icon: Home }];

  const companies = payload?.companies ?? [];
  for (const c of companies) {
    const pending = isReviewPending(c);
    items.push({
      to: `/reviewer/companies/${c.id}`,
      label: c.name,
      icon: Building2,
      section: 'Your companies',
      badge: pending ? 'Review' : undefined,
      badgeTone: pending ? 'attention' : 'default',
    });
  }

  const unread = payload?.unread_count ?? 0;
  items.push({
    to: '/reviewer/inbox',
    label: 'Inbox',
    icon: Inbox,
    badge: unread > 0 ? String(unread) : undefined,
    badgeTone: 'attention',
  });
  items.push({ to: '/reviewer/profile', label: 'Profile', icon: UserCircle });

  return items;
}

/** Static base nav (no assignments) — safe fallback if the layout fetch fails. */
export const navItems: SidebarItem[] = reviewerNavItems(null);
