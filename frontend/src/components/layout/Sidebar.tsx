import { Link } from 'react-router-dom';
import type { LucideIcon } from 'lucide-react';
import type { ReactNode } from 'react';
import { cn } from '../../lib/cn';
import { Sheet, SheetContent } from '@/components/shadcn/sheet';
import { ScrollArea } from '@/components/shadcn/scroll-area';
import { Separator } from '@/components/shadcn/separator';

export type SidebarItem = {
  to: string;
  label: string;
  icon: LucideIcon;
  section?: string;
  badge?: string;
  badgeTone?: 'default' | 'attention';
};

type SidebarProps = {
  logo: string;
  items: SidebarItem[];
  activePath: string;
  footer?: ReactNode;
  mobileOpen?: boolean;
  onMobileClose?: () => void;
};

function isItemActive(activePath: string, to: string) {
  if (activePath === to) return true;
  if (to === '/') return false;
  return activePath.startsWith(`${to}/`);
}

function SidebarNav({
  logo,
  items,
  activePath,
  footer,
  onNavigate,
}: SidebarProps & { onNavigate?: () => void }) {
  return (
    <div className="flex h-full flex-col bg-sidebar text-sidebar-foreground">
      <div className="flex h-topbar shrink-0 items-center gap-3 border-b border-sidebar-border px-5 pr-12 md:pr-5">
        <span className="h-5 w-[3px] shrink-0 rounded-full bg-primary" aria-hidden />
        <span className="truncate font-display text-[15px] font-semibold tracking-tight text-sidebar-strong">
          {logo}
        </span>
      </div>

      <ScrollArea className="flex-1 px-3 py-4">
        <nav className="flex flex-col gap-0.5">
          {items.map(({ to, label, icon: Icon, section, badge, badgeTone }, index) => {
            const active = isItemActive(activePath, to);
            const prevSection = index > 0 ? items[index - 1]?.section : undefined;
            const showSection = section && section !== prevSection;
            return (
              <div key={to}>
                {showSection && (
                  <p className="mb-1 mt-4 px-3.5 text-[10px] font-semibold uppercase tracking-[0.14em] text-sidebar-foreground/70 first:mt-0">
                    {section}
                  </p>
                )}
                <Link
                  to={to}
                  onClick={onNavigate}
                  aria-current={active ? 'page' : undefined}
                  className={cn(
                    'group relative flex items-center gap-3 rounded-md px-3.5 py-2 text-sm font-medium transition-colors',
                    active
                      ? 'text-sidebar-strong'
                      : 'text-sidebar-foreground hover:bg-sidebar-hover hover:text-sidebar-strong'
                  )}
                >
                  {active && (
                    <span
                      className="absolute left-0 top-1/2 h-5 w-[3px] -translate-y-1/2 rounded-r-full bg-primary"
                      aria-hidden
                    />
                  )}
                  <Icon
                    className={cn(
                      'h-[17px] w-[17px] shrink-0 transition-colors',
                      active ? 'text-primary' : 'text-sidebar-foreground group-hover:text-sidebar-strong'
                    )}
                    aria-hidden
                  />
                  <span className="flex-1">{label}</span>
                  {badge && (
                    <span
                      className={cn(
                        'rounded-full px-1.5 py-0.5 text-[10px] font-semibold tabular-nums',
                        badgeTone === 'attention'
                          ? 'bg-status-warning/20 text-status-warning'
                          : 'bg-white/10 text-sidebar-foreground'
                      )}
                    >
                      {badge}
                    </span>
                  )}
                </Link>
              </div>
            );
          })}
        </nav>
      </ScrollArea>

      {footer ? (
        <>
          <Separator className="bg-sidebar-border" />
          <div className="shrink-0 p-3">{footer}</div>
        </>
      ) : null}
    </div>
  );
}

export function Sidebar({ logo, items, activePath, footer, mobileOpen, onMobileClose }: SidebarProps) {
  return (
    <>
      <aside className="fixed left-0 top-0 z-40 hidden h-screen w-sidebar border-r border-sidebar-border md:block">
        <SidebarNav logo={logo} items={items} activePath={activePath} footer={footer} />
      </aside>

      <Sheet open={mobileOpen} onOpenChange={(open) => !open && onMobileClose?.()}>
        <SheetContent side="left" className="w-sidebar p-0 sm:max-w-sidebar">
          <SidebarNav
            logo={logo}
            items={items}
            activePath={activePath}
            footer={footer}
            onNavigate={onMobileClose}
          />
        </SheetContent>
      </Sheet>
    </>
  );
}
