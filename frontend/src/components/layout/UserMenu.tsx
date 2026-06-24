import { LogOut } from 'lucide-react';
import { cn } from '../../lib/cn';
import { Button } from '../ui/Button';
import { Badge } from '@/components/shadcn/badge';

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
        <span className="block truncate text-sm font-medium text-foreground">{name}</span>
        <span className="block truncate text-xs text-muted-foreground">{email}</span>
      </div>
      {roleBadge ? (
        <Badge variant="secondary" className={cn('w-fit text-[0.6875rem] uppercase tracking-wide')}>
          {roleBadge}
        </Badge>
      ) : null}
      <Button
        type="button"
        variant="ghost"
        size="sm"
        icon={<LogOut className="h-4 w-4" />}
        onClick={onLogout}
        className="w-full justify-start text-muted-foreground hover:text-foreground"
      >
        {logoutLabel}
      </Button>
    </div>
  );
}
