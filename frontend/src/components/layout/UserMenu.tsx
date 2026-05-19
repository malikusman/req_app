import { LogOut } from 'lucide-react';
import { cn } from '../../lib/cn';
import { Button } from '../ui/Button';

export type UserMenuProps = {
  name: string;
  email: string;
  roleBadge?: string;
  onLogout: () => void;
  logoutLabel?: string;
};

export function UserMenu({ name, email, roleBadge, onLogout, logoutLabel = 'Log out' }: UserMenuProps) {
  return (
    <div className="flex flex-col gap-3">
      <div className="min-w-0">
        <span className="block truncate text-sm font-medium text-white">{name}</span>
        <span className="block truncate text-xs text-text-inverse/60">{email}</span>
      </div>
      {roleBadge ? (
        <span
          className={cn(
            'inline-flex w-fit items-center rounded-badge px-2 py-0.5',
            'bg-white/10 text-[0.6875rem] font-semibold uppercase tracking-wide text-text-inverse/90'
          )}
        >
          {roleBadge}
        </span>
      ) : null}
      <Button
        type="button"
        variant="ghost"
        size="sm"
        icon={<LogOut className="h-4 w-4" />}
        onClick={onLogout}
        className="w-full justify-start border border-white/15 text-text-inverse hover:bg-white/10 hover:text-white"
      >
        {logoutLabel}
      </Button>
    </div>
  );
}
