import { type ReactNode } from 'react';
import { motion, useReducedMotion } from 'motion/react';
import { TrendingDown, TrendingUp } from 'lucide-react';
import { cn } from '../../lib/cn';
import { spring } from '../../lib/motion';

export function StatCard({
  label,
  value,
  suffix,
  trend,
  icon,
  className,
}: {
  label: string;
  value: string | number;
  suffix?: string;
  trend?: { value: number; label?: string };
  icon?: ReactNode;
  className?: string;
}) {
  const reduced = useReducedMotion();
  const trendUp = trend && trend.value >= 0;

  const content = (
    <>
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
          <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-button bg-accent-muted text-accent">
            {icon}
          </div>
        )}
      </div>
    </>
  );

  if (reduced) {
    return (
      <div
        className={cn(
          'rounded-card border border-border bg-surface p-5 shadow-card',
          className
        )}
      >
        {content}
      </div>
    );
  }

  return (
    <motion.div
      className={cn(
        'rounded-card border border-border bg-surface p-5 shadow-card',
        className
      )}
      whileHover={{ y: -2, boxShadow: '0 0 0 1px rgba(255,255,255,0.09), 0 18px 42px rgba(0,0,0,0.36)' }}
      transition={spring.soft}
    >
      {content}
    </motion.div>
  );
}
