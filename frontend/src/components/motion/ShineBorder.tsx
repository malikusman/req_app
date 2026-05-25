import { type ReactNode } from 'react';
import { cn } from '../../lib/cn';

/** Subtle animated border shimmer — Magic UI–inspired, zero extra deps. */
export function ShineBorder({
  children,
  className,
  borderWidth = 1,
}: {
  children: ReactNode;
  className?: string;
  borderWidth?: number;
}) {
  return (
    <div
      className={cn('relative rounded-card', className)}
      style={{ padding: borderWidth }}
    >
      <div
        className="pointer-events-none absolute inset-0 overflow-hidden rounded-[inherit] motion-reduce:hidden"
        aria-hidden
      >
        <div className="absolute inset-[-100%] animate-shine bg-[conic-gradient(from_0deg,transparent_0deg,rgba(79,70,229,0.35)_90deg,transparent_180deg)] opacity-80" />
      </div>
      <div className="relative rounded-[inherit] bg-surface">{children}</div>
    </div>
  );
}
