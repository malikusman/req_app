import { Link } from 'react-router-dom';
import type { LucideIcon } from 'lucide-react';
import type { ReactNode } from 'react';
import { cn } from '../../lib/cn';

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
};

function isItemActive(activePath: string, to: string) {
  if (activePath === to) return true;
  if (to === '/') return false;
  return activePath.startsWith(`${to}/`);
}

export function Sidebar({ logo, items, activePath, footer }: SidebarProps) {
  return (
    <aside
      className={cn(
        'fixed left-0 top-0 z-40 flex h-screen w-sidebar flex-col',
        'bg-sidebar text-text-inverse'
      )}
    >
      <div className="flex h-topbar shrink-0 items-center border-b border-white/10 px-5">
        <span className="font-display text-sm font-semibold tracking-tight">{logo}</span>
      </div>

      <nav className="flex flex-1 flex-col gap-0.5 overflow-y-auto px-3 py-4">
        {items.map(({ to, label, icon: Icon }) => {
          const active = isItemActive(activePath, to);
          return (
            <Link
              key={to}
              to={to}
              className={cn(
                'flex items-center gap-3 rounded-md px-3 py-2.5 text-sm font-medium transition-colors',
                'border-l-[3px] border-transparent',
                active
                  ? 'border-l-accent bg-sidebar-active text-white'
                  : 'text-text-inverse/70 hover:bg-sidebar-hover hover:text-white'
              )}
            >
              <Icon className="h-[18px] w-[18px] shrink-0 opacity-90" aria-hidden />
              <span>{label}</span>
            </Link>
          );
        })}
      </nav>

      {footer ? <div className="shrink-0 border-t border-white/10 p-3">{footer}</div> : null}
    </aside>
  );
}
