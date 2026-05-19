import { motion } from 'motion/react';
import { cn } from '../../lib/cn';

export type HeatmapCell = {
  department: string;
  completed: number;
  target: number;
};

function cellColor(ratio: number): string {
  if (ratio >= 1) return 'bg-status-success text-white';
  if (ratio >= 0.75) return 'bg-status-success/80 text-white';
  if (ratio >= 0.5) return 'bg-status-warning/70 text-text-primary';
  if (ratio >= 0.25) return 'bg-status-warning/40 text-text-primary';
  return 'bg-status-error/30 text-text-primary';
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
      className={cn('grid gap-2 sm:grid-cols-2 lg:grid-cols-3', className)}
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
            className={cn('rounded-card p-4', cellColor(ratio))}
          >
            <p className="text-sm font-semibold">{cell.department}</p>
            <p className="mt-1 text-xs opacity-90">
              {cell.completed} / {cell.target} ({pct}%)
            </p>
          </motion.div>
        );
      })}
    </motion.div>
  );
}
