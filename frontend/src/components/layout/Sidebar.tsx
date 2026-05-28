import { Link } from 'react-router-dom';
import type { LucideIcon } from 'lucide-react';
import { motion, useReducedMotion } from 'motion/react';
import { X } from 'lucide-react';
import type { ReactNode } from 'react';
import { cn } from '../../lib/cn';
import { spring } from '../../lib/motion';

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

export function Sidebar({ logo, items, activePath, footer, mobileOpen, onMobileClose }: SidebarProps) {
  const reduced = useReducedMotion();

  return (
    <>
      {mobileOpen && (
        <button
          type="button"
          className="fixed inset-0 z-40 bg-black/50 md:hidden"
          aria-label="Close menu"
          onClick={onMobileClose}
        />
      )}
      <aside
        className={cn(
          'fixed left-0 top-0 z-50 flex h-screen w-sidebar flex-col bg-sidebar text-text-inverse transition-transform duration-200 md:translate-x-0',
          mobileOpen ? 'translate-x-0' : '-translate-x-full md:translate-x-0'
        )}
      >
        <div className="flex h-topbar shrink-0 items-center justify-between border-b border-white/10 px-5">
          <span className="font-display text-sm font-semibold tracking-tight text-white">{logo}</span>
          {onMobileClose && (
            <button
              type="button"
              className="rounded-md p-1 text-white/70 hover:text-white md:hidden"
              onClick={onMobileClose}
              aria-label="Close navigation"
            >
              <X className="h-5 w-5" />
            </button>
          )}
        </div>

        <nav className="flex flex-1 flex-col gap-0.5 overflow-y-auto px-3 py-4">
          {items.map(({ to, label, icon: Icon }) => {
            const active = isItemActive(activePath, to);
            return (
              <Link
                key={to}
                to={to}
                onClick={onMobileClose}
                className={cn(
                  'relative flex items-center gap-3 rounded-md px-3 py-2.5 text-sm font-medium',
                  active ? 'text-white' : 'text-white/65 hover:text-white/95'
                )}
              >
                {active && !reduced && (
                  <motion.span
                    layoutId="sidebar-active-pill"
                    className="absolute inset-0 rounded-md border-l-2 border-l-accent bg-sidebar-active/90"
                    transition={spring.soft}
                  />
                )}
                {active && reduced && (
                  <span className="absolute inset-0 rounded-md border-l-2 border-l-accent bg-sidebar-active/90" />
                )}
                <Icon className="relative z-10 h-[18px] w-[18px] shrink-0" aria-hidden />
                <span className="relative z-10">{label}</span>
              </Link>
            );
          })}
        </nav>

        {footer ? <div className="shrink-0 border-t border-white/10 p-3">{footer}</div> : null}
      </aside>
    </>
  );
}
