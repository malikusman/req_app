import { type ReactNode } from 'react';
import { Link } from 'react-router-dom';
import { cn } from '../../lib/cn';

/**
 * A number paired with a verb — status that offers its next move. Replaces the
 * old jargon KPI row.
 */
export function OutcomeTile({
  icon,
  label,
  value,
  valueSuffix,
  action,
  className,
}: {
  icon?: ReactNode;
  label: string;
  value: ReactNode;
  valueSuffix?: string;
  action: { label: string; to: string };
  className?: string;
}) {
  return (
    <Link
      to={action.to}
      className={cn(
        'group flex flex-col gap-1 rounded-card border border-border bg-card p-4 transition-colors hover:border-border-strong hover:shadow-card focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring sm:p-5',
        className
      )}
    >
      {icon && (
        <span className="mb-1 flex h-8 w-8 items-center justify-center rounded-md bg-accent-muted text-accent-hover">
          {icon}
        </span>
      )}
      <span className="text-xs font-semibold text-muted-foreground">{label}</span>
      <span className="font-display text-3xl font-semibold leading-none tabular-nums text-foreground">
        {value}
        {valueSuffix && <span className="ml-1 text-sm font-semibold text-muted-foreground">{valueSuffix}</span>}
      </span>
      <span className="mt-1.5 text-xs font-semibold text-accent-hover group-hover:underline">
        {action.label} →
      </span>
    </Link>
  );
}
