import { motion } from 'motion/react';
import { cn } from '../../lib/cn';

type Size = 'sm' | 'md';

const sizes: Record<Size, string> = {
  sm: 'h-1.5',
  md: 'h-2.5',
};

export function ProgressBar({
  value,
  size = 'md',
  className,
}: {
  value: number;
  size?: Size;
  className?: string;
}) {
  const clamped = Math.min(100, Math.max(0, value));

  return (
    <div
      className={cn('w-full overflow-hidden rounded-full bg-muted', sizes[size], className)}
      role="progressbar"
      aria-valuenow={clamped}
      aria-valuemin={0}
      aria-valuemax={100}
    >
      <motion.div
        className="h-full rounded-full bg-primary"
        initial={{ width: 0 }}
        animate={{ width: `${clamped}%` }}
        transition={{ duration: 0.4, ease: 'easeOut' }}
      />
    </div>
  );
}
