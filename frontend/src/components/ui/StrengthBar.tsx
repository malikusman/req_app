import { motion } from 'motion/react';
import { cn } from '../../lib/cn';

const strengthColors = [
  'bg-status-error',
  'bg-status-warning',
  'bg-status-warning',
  'bg-status-success',
  'bg-status-success',
];

function strengthLabel(value: number): string {
  if (value < 0.25) return 'Weak';
  if (value < 0.5) return 'Fair';
  if (value < 0.75) return 'Good';
  return 'Strong';
}

export function StrengthBar({
  strength,
  label,
  className,
}: {
  strength: number;
  label?: string;
  className?: string;
}) {
  const clamped = Math.min(1, Math.max(0, strength));
  const segments = 4;
  const filled = Math.ceil(clamped * segments);
  const displayLabel = label ?? strengthLabel(clamped);

  return (
    <motion.div className={cn('flex flex-col gap-1.5', className)} layout>
      {displayLabel && (
        <span className="text-xs font-medium text-text-secondary">{displayLabel}</span>
      )}
      <div className="flex gap-1">
        {Array.from({ length: segments }).map((_, i) => (
          <motion.div
            key={i}
            className={cn(
              'h-1.5 flex-1 rounded-badge',
              i < filled ? strengthColors[filled - 1] : 'bg-border'
            )}
            initial={{ scaleX: 0 }}
            animate={{ scaleX: 1 }}
            transition={{ delay: i * 0.05, duration: 0.2 }}
          />
        ))}
      </div>
    </motion.div>
  );
}
