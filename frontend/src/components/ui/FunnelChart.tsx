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
      className={cn('flex min-w-0 flex-col gap-2', className)}
    >
      {stages.map((stage, i) => {
        const widthPct = (stage.count / max) * 100;
        return (
          <motion.div
            key={stage.label}
            initial={{ opacity: 0, x: -12 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: i * 0.06 }}
            className="flex min-w-0 flex-col gap-1"
          >
            <div className="flex items-center justify-between gap-2 text-sm">
              <span className="truncate font-medium text-foreground">{stage.label}</span>
              <span className="shrink-0 tabular-nums text-muted-foreground">{stage.count.toLocaleString()}</span>
            </div>
            <div className="h-8 min-w-0 overflow-hidden rounded-md bg-muted">
              <motion.div
                className="flex h-full min-w-0 items-center rounded-md bg-primary px-3 text-xs font-medium text-primary-foreground"
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
