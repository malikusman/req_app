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
  platform: 'Worktruth — Platform',
  company: 'Worktruth — Company',
  reviewer: 'Worktruth — Reviewer',
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
  fullBleed?: boolean;
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
  fullBleed = false,
  children,
}: PortalShellProps) {
  const { pathname } = useLocation();
  const resolvedLogo = logo ?? defaultLogos[portal];
  const [sidebarOpen, setSidebarOpen] = useState(false);

  return (
    <div className={cn('bg-surface-muted', fullBleed ? 'h-dvh overflow-hidden' : 'min-h-dvh')}>
      <Sidebar
        logo={resolvedLogo}
        items={navItems}
        activePath={pathname}
        footer={sidebarFooter ?? <UserMenu {...userMenu} />}
        mobileOpen={sidebarOpen}
        onMobileClose={() => setSidebarOpen(false)}
      />
      <div
        className={cn(
          'flex flex-col md:pl-sidebar',
          fullBleed ? 'h-full min-h-0' : 'min-h-dvh'
        )}
      >
        <TopBar
          title={title}
          subtitle={subtitle}
          actions={topBarActions}
          onMenuClick={() => setSidebarOpen(true)}
        />
        <main
          className={cn(
            'min-h-0 flex-1',
            fullBleed ? 'overflow-hidden' : 'overflow-y-auto overflow-x-hidden'
          )}
        >
          <div
            className={cn(
              fullBleed
                ? 'flex h-full min-h-0 flex-col'
                : 'mx-auto max-w-content bg-surface-muted p-4 md:p-8'
            )}
          >
            <PageTransition className={fullBleed ? 'flex min-h-0 flex-1 flex-col' : undefined}>
              {children ?? <Outlet />}
            </PageTransition>
          </div>
        </main>
      </div>
    </div>
  );
}
