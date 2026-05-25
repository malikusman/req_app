import { type ReactNode } from 'react';
import { cn } from '../../lib/cn';
import { Stagger } from './Stagger';

export function StatCardGrid({
  children,
  className,
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <Stagger
      className={cn('grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4', className)}
      staggerDelay={0.07}
    >
      {children}
    </Stagger>
  );
}
