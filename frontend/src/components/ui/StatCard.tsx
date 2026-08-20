import { type ReactNode } from 'react';
import { TrendingDown, TrendingUp } from 'lucide-react';
import { cn } from '../../lib/cn';

export function StatCard({
  label,
  value,
  suffix,
  trend,
  icon,
  className,
}: {
  label: string;
  value: ReactNode;
  suffix?: string;
  trend?: { value: number; label?: string };
  icon?: ReactNode;
  className?: string;
}) {
  const trendUp = trend && trend.value >= 0;

  return (
    <div
      className={cn(
        // Work surface: flat, defined by a border — elevation is reserved for the
        // one hero per screen, not spent on every stat.
        'rounded-card border border-border-strong bg-surface p-5',
        className
      )}
    >
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0 flex-1">
          <p className="text-label-caps uppercase text-text-secondary">{label}</p>
          <p className="mt-2 font-display text-2xl font-semibold text-text-primary">
            {value}
            {suffix && (
              <span className="ml-1 text-base font-normal text-text-secondary">{suffix}</span>
            )}
          </p>
          {trend && (
            <div
              className={cn(
                'mt-2 flex items-center gap-1 text-xs font-medium',
                trendUp ? 'text-status-success' : 'text-status-error'
              )}
            >
              {trendUp ? (
                <TrendingUp className="h-3.5 w-3.5" />
              ) : (
                <TrendingDown className="h-3.5 w-3.5" />
              )}
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
    </div>
  );
}
