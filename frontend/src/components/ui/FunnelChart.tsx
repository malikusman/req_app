import { motion } from 'motion/react';
import { cn } from '../../lib/cn';

export type FunnelStage = { label: string; count: number };

export function FunnelChart({
  stages,
  className,
}: {
  stages: FunnelStage[];
  className?: string;
}) {
  const max = Math.max(...stages.map((s) => s.count), 1);

  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      className={cn('flex flex-col gap-2', className)}
    >
      {stages.map((stage, i) => {
        const widthPct = (stage.count / max) * 100;
        return (
          <motion.div
            key={stage.label}
            initial={{ opacity: 0, x: -12 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: i * 0.06 }}
            className="flex flex-col gap-1"
          >
            <motion.div className="flex items-center justify-between text-sm">
              <span className="font-medium text-text-primary">{stage.label}</span>
              <span className="text-text-secondary">{stage.count.toLocaleString()}</span>
            </motion.div>
            <div className="h-8 w-full overflow-hidden rounded-button bg-surface-muted">
              <motion.div
                className="flex h-full items-center rounded-button bg-accent px-3 text-xs font-medium text-white"
                initial={{ width: 0 }}
                animate={{ width: `${widthPct}%` }}
                transition={{ duration: 0.4, delay: i * 0.05 }}
              >
                {widthPct > 20 && `${Math.round(widthPct)}%`}
              </motion.div>
            </div>
          </motion.div>
        );
      })}
    </motion.div>
  );
}
