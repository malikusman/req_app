import type { ReactNode } from 'react';
import { cn } from '../../lib/cn';

type TopBarProps = {
  title: string;
  subtitle?: string;
  actions?: ReactNode;
};

export function TopBar({ title, subtitle, actions }: TopBarProps) {
  return (
    <header
      className={cn(
        'flex h-topbar shrink-0 items-center justify-between gap-4',
        'border-b border-border bg-surface px-8'
      )}
    >
      <div className="min-w-0">
        <h1 className="truncate font-display text-page-title text-text-primary">{title}</h1>
        {subtitle ? (
          <p className="truncate text-sm text-text-secondary">{subtitle}</p>
        ) : null}
      </div>
      {actions ? <div className="flex shrink-0 items-center gap-3">{actions}</div> : null}
    </header>
  );
}
