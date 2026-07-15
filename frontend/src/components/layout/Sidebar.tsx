import { Link } from 'react-router-dom';
import type { LucideIcon } from 'lucide-react';
import { motion, useReducedMotion } from 'motion/react';
import type { ReactNode } from 'react';
import { cn } from '../../lib/cn';
import { spring } from '../../lib/motion';
import { Sheet, SheetContent } from '@/components/shadcn/sheet';
import { ScrollArea } from '@/components/shadcn/scroll-area';
import { Separator } from '@/components/shadcn/separator';

export type SidebarItem = {
  to: string;
  label: string;
  icon: LucideIcon;
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
  const reduced = useReducedMotion();

  return (
    <div className="flex h-full flex-col bg-sidebar text-sidebar-foreground">
      <div className="flex h-topbar shrink-0 items-center border-b border-sidebar-border px-5 pr-12 md:pr-5">
        <span className="truncate text-sm font-semibold tracking-tight text-foreground">{logo}</span>
      </div>

      <ScrollArea className="flex-1 px-3 py-4">
        <nav className="flex flex-col gap-0.5">
          {items.map(({ to, label, icon: Icon }) => {
            const active = isItemActive(activePath, to);
            return (
              <Link
                key={to}
                to={to}
                onClick={onNavigate}
                className={cn(
                  'relative flex items-center gap-3 rounded-full px-3.5 py-2.5 text-sm font-medium transition-colors',
                  active
                    ? 'text-sidebar-accent-foreground'
                    : 'text-sidebar-foreground hover:bg-sidebar-hover hover:text-foreground'
                )}
              >
                {active && !reduced && (
                  <motion.span
                    layoutId="sidebar-active-pill"
                    className="absolute inset-0 rounded-full bg-sidebar-accent"
                    transition={spring.soft}
                  />
                )}
                {active && reduced && (
                  <span className="absolute inset-0 rounded-full bg-sidebar-accent" />
                )}
                <Icon className="relative z-10 h-[18px] w-[18px] shrink-0" aria-hidden />
                <span className="relative z-10">{label}</span>
              </Link>
            );
          })}
        </nav>
      </ScrollArea>

      {footer ? (
        <>
          <Separator />
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
