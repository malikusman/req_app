import type { ReactNode } from 'react';
import { Menu } from 'lucide-react';
import { cn } from '../../lib/cn';

type TopBarProps = {
  title: string;
  subtitle?: string;
  actions?: ReactNode;
  onMenuClick?: () => void;
};

export function TopBar({ title, subtitle, actions, onMenuClick }: TopBarProps) {
  return (
    <header
      className={cn(
        'flex h-topbar shrink-0 items-center justify-between gap-4',
        'border-b border-border bg-white px-4 md:px-8'
      )}
    >
      <div className="flex min-w-0 items-center gap-3">
        {onMenuClick && (
          <button
            type="button"
            className="rounded-md p-2 text-text-secondary hover:bg-surface-muted md:hidden"
            onClick={onMenuClick}
            aria-label="Open menu"
          >
            <Menu className="h-5 w-5" />
          </button>
        )}
        <div className="min-w-0">
          <h1 className="truncate font-display text-page-title text-text-primary">{title}</h1>
          {subtitle ? (
            <p className="truncate text-sm text-text-secondary">{subtitle}</p>
          ) : null}
        </div>
      </div>
      {actions ? <div className="flex shrink-0 items-center gap-3">{actions}</div> : null}
    </header>
  );
}
