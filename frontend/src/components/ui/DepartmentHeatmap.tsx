import { motion } from 'motion/react';
import { cn } from '../../lib/cn';

export type HeatmapCell = {
  department: string;
  completed: number;
  target: number;
};

function cellColor(ratio: number): string {
  if (ratio >= 1) return 'bg-success text-success-foreground';
  if (ratio >= 0.75) return 'bg-success/80 text-success-foreground';
  if (ratio >= 0.5) return 'bg-warning/70 text-warning-foreground';
  if (ratio >= 0.25) return 'bg-warning/40 text-foreground';
  return 'bg-destructive/20 text-foreground';
}

export function DepartmentHeatmap({
  cells,
  className,
}: {
  cells: HeatmapCell[];
  className?: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      className={cn('grid min-w-0 gap-2 sm:grid-cols-2', className)}
    >
      {cells.map((cell, i) => {
        const ratio = cell.target > 0 ? cell.completed / cell.target : 0;
        const pct = Math.round(ratio * 100);
        return (
          <motion.div
            key={cell.department}
            initial={{ opacity: 0, scale: 0.96 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ delay: i * 0.04 }}
            className={cn('min-w-0 rounded-lg p-3 sm:p-4', cellColor(ratio))}
          >
            <p className="truncate text-sm font-semibold">{cell.department}</p>
            <p className="mt-1 text-xs opacity-90">
              {cell.completed} / {cell.target} ({pct}%)
            </p>
          </motion.div>
        );
      })}
    </motion.div>
  );
}
