import { useState } from 'react';
import { Outlet, useLocation } from 'react-router-dom';
import type { ReactNode } from 'react';
import type { Portal } from '../../lib/auth';
import { cn } from '../../lib/cn';
import { PageTransition } from '../motion/PageTransition';
import { Sidebar, type SidebarItem } from './Sidebar';
import { TopBar } from './TopBar';
import { UserMenu, type UserMenuProps } from './UserMenu';

const defaultLogos: Record<Portal, string> = {
  platform: 'Req — Platform',
  company: 'Company Portal',
  reviewer: 'Req — Reviewer',
};

export type PortalShellProps = {
  portal: Portal;
  navItems: SidebarItem[];
  userMenu: UserMenuProps;
  logo?: string;
  title: string;
  subtitle?: string;
  topBarActions?: ReactNode;
  sidebarFooter?: ReactNode;
  children?: ReactNode;
};

export function PortalShell({
  portal,
  navItems,
  userMenu,
  logo,
  title,
  subtitle,
  topBarActions,
  sidebarFooter,
  children,
}: PortalShellProps) {
  const { pathname } = useLocation();
  const resolvedLogo = logo ?? defaultLogos[portal];
  const [sidebarOpen, setSidebarOpen] = useState(false);

  return (
    <div className="portal relative min-h-screen overflow-hidden bg-surface-muted">
      <div
        className="pointer-events-none absolute inset-0 opacity-[0.06] bg-[length:64px_64px] bg-[linear-gradient(rgba(255,255,255,0.08)_1px,transparent_1px),linear-gradient(90deg,rgba(255,255,255,0.08)_1px,transparent_1px)]"
        aria-hidden
      />
      <Sidebar
        logo={resolvedLogo}
        items={navItems}
        activePath={pathname}
        footer={sidebarFooter ?? <UserMenu {...userMenu} />}
        mobileOpen={sidebarOpen}
        onMobileClose={() => setSidebarOpen(false)}
      />
      <div className={cn('relative z-10 flex min-h-screen flex-col', 'md:pl-sidebar')}>
        <TopBar
          title={title}
          subtitle={subtitle}
          actions={topBarActions}
          onMenuClick={() => setSidebarOpen(true)}
        />
        <main className="flex-1 overflow-y-auto">
          <div className="mx-auto max-w-content bg-surface-muted p-4 md:p-8">
            <PageTransition>{children ?? <Outlet />}</PageTransition>
          </div>
        </main>
      </div>
    </div>
  );
}
