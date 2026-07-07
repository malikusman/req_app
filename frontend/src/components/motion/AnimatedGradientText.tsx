import { type ReactNode } from 'react';
import { useReducedMotion } from 'motion/react';
import { cn } from '../../lib/cn';

/** Magic UI–style shifting gradient on headline accents. */
export function AnimatedGradientText({
  children,
  className,
}: {
  children: ReactNode;
  className?: string;
}) {
  const reduced = useReducedMotion();

  if (reduced) {
    return <span className={cn('text-accent', className)}>{children}</span>;
  }

  return (
    <span
      className={cn(
        'animate-text-gradient bg-gradient-to-r from-accent via-emerald-300 to-accent bg-[length:200%_auto] bg-clip-text text-transparent',
        className
      )}
    >
      {children}
    </span>
  );
}
