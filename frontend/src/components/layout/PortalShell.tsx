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
    <div className="min-h-screen bg-surface-muted">
      <Sidebar
        logo={resolvedLogo}
        items={navItems}
        activePath={pathname}
        footer={sidebarFooter ?? <UserMenu {...userMenu} />}
        mobileOpen={sidebarOpen}
        onMobileClose={() => setSidebarOpen(false)}
      />
      <div className={cn('flex min-h-screen flex-col', 'md:pl-sidebar')}>
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
