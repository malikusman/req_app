import { type ReactNode } from 'react';
import { cn } from '../../lib/cn';

/**
 * The card that holds each sign-in form. It used to spin an indigo conic
 * gradient round the edge forever — a leftover from the old theme, and motion
 * on a page whose only job is a form. Now a plain bordered card; the name stays
 * so the call sites need not change.
 */
export function ShineBorder({ children, className }: { children: ReactNode; className?: string; borderWidth?: number }) {
  return <div className={cn('rounded-card border border-border bg-card', className)}>{children}</div>;
}
