import { type ReactNode } from 'react';
import { Menu } from 'lucide-react';
import { cn } from '../../lib/cn';
import { Button } from '@/components/shadcn/button';

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
        'border-b border-border bg-card px-4 md:px-8'
      )}
    >
      <div className="flex min-w-0 items-center gap-3">
        {onMenuClick && (
          <Button
            type="button"
            variant="ghost"
            size="icon"
            className="md:hidden"
            onClick={onMenuClick}
            aria-label="Open menu"
          >
            <Menu className="h-5 w-5" />
          </Button>
        )}
        <div className="min-w-0">
          <h1 className="truncate text-base font-semibold text-foreground md:text-page-title">{title}</h1>
          {subtitle ? (
            <p className="truncate text-sm text-muted-foreground">{subtitle}</p>
          ) : null}
        </div>
      </div>
      {actions ? <div className="flex shrink-0 items-center gap-3">{actions}</div> : null}
    </header>
  );
}
