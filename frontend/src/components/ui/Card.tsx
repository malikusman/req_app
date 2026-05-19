import { type ReactNode } from 'react';
import { cn } from '../../lib/cn';

export function Card({
  title,
  children,
  className,
  padding = true,
}: {
  title?: string;
  children: ReactNode;
  className?: string;
  padding?: boolean;
}) {
  return (
    <div className={cn('rounded-card border border-border bg-surface shadow-card', padding && 'p-6', className)}>
      {title && <h3 className="font-display text-section-title text-text-primary mb-4 mt-0">{title}</h3>}
      {children}
    </div>
  );
}
