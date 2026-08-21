import { type ReactNode } from 'react';
import { Link } from 'react-router-dom';
import { TrendingDown, TrendingUp } from 'lucide-react';
import { cn } from '../../lib/cn';

export function StatCard({
  label,
  value,
  suffix,
  trend,
  icon,
  to,
  className,
}: {
  label: string;
  value: ReactNode;
  suffix?: string;
  trend?: { value: number; label?: string };
  icon?: ReactNode;
  /** When set, the whole card links to its worklist — a stat you can act on. */
  to?: string;
  className?: string;
}) {
  const trendUp = trend && trend.value >= 0;

  const body = (
    <div className="flex items-start justify-between gap-3">
      <div className="min-w-0 flex-1">
        <p className="text-label-caps uppercase text-text-secondary">{label}</p>
        <p className="mt-2 font-display text-2xl font-semibold text-text-primary">
          {value}
          {suffix && <span className="ml-1 text-base font-normal text-text-secondary">{suffix}</span>}
        </p>
        {trend && (
          <div
            className={cn(
              'mt-2 flex items-center gap-1 text-xs font-medium',
              trendUp ? 'text-status-success' : 'text-status-error'
            )}
          >
            {trendUp ? <TrendingUp className="h-3.5 w-3.5" /> : <TrendingDown className="h-3.5 w-3.5" />}
            <span>
              {trendUp ? '+' : ''}
              {trend.value}%
            </span>
            {trend.label && <span className="text-text-secondary font-normal">{trend.label}</span>}
          </div>
        )}
      </div>
      {icon && (
        <span className="shrink-0 text-text-secondary [&>svg]:h-5 [&>svg]:w-5" aria-hidden>
          {icon}
        </span>
      )}
    </div>
  );

  // Work surface: flat, defined by a border — elevation is reserved for the one
  // hero per screen, not spent on every stat.
  const base = 'rounded-card border border-border-strong bg-surface p-5';

  if (to) {
    return (
      <Link
        to={to}
        className={cn(
          base,
          'group block transition-colors hover:border-accent/60 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
          className
        )}
      >
        {body}
      </Link>
    );
  }

  return <div className={cn(base, className)}>{body}</div>;
}
