import { motion } from 'motion/react';
import { cn } from '../../lib/cn';

/**
 * Two different scales were being drawn with one ramp.
 *
 * `quality` is the original: low is bad (red), high is good (green). Right for
 * a confidence or a readiness score.
 *
 * `evidence` is for how much evidence sits behind a FRICTION. On that scale the
 * red-to-green ramp is actively wrong — a heavily-evidenced problem rendered
 * green, as though it were good news, on the client's own dashboard. Evidence
 * has no polarity, so it deepens in neutral ink and the severity badge beside
 * it carries the judgement.
 */
const strengthColors = [
  'bg-status-error',
  'bg-status-warning',
  'bg-status-warning',
  'bg-status-success',
  'bg-status-success',
];

const evidenceColors = [
  'bg-foreground/25',
  'bg-foreground/45',
  'bg-foreground/65',
  'bg-foreground/85',
  'bg-foreground/85',
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
  tone = 'quality',
  className,
}: {
  strength: number;
  label?: string;
  tone?: 'quality' | 'evidence';
  className?: string;
}) {
  const clamped = Math.min(1, Math.max(0, strength));
  const segments = 4;
  const filled = Math.ceil(clamped * segments);
  const displayLabel = label ?? strengthLabel(clamped);
  const ramp = tone === 'evidence' ? evidenceColors : strengthColors;

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
              i < filled ? ramp[filled - 1] : 'bg-border'
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
