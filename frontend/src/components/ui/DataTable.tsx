import { type ReactNode } from 'react';
import { motion } from 'motion/react';
import { cn } from '../../lib/cn';
import { Skeleton } from './Skeleton';

export type Column<T> = {
  key: string;
  header: string;
  render?: (row: T) => ReactNode;
  className?: string;
};

export function DataTable<T extends object>({
  columns,
  rows,
  onRowClick,
  loading,
  emptyState,
  className,
  getRowKey = (row, i) => String((row as { id?: unknown }).id ?? i),
}: {
  columns: Column<T>[];
  rows: T[];
  onRowClick?: (row: T) => void;
  loading?: boolean;
  emptyState?: ReactNode;
  className?: string;
  getRowKey?: (row: T, index: number) => string;
}) {
  if (loading) {
    return (
      <motion.div className={cn('overflow-hidden rounded-card border border-border bg-surface', className)}>
        {Array.from({ length: 5 }).map((_, i) => (
          <Skeleton key={i} variant="table-row" />
        ))}
      </motion.div>
    );
  }

  if (rows.length === 0 && emptyState) {
    return <motion.div className={className}>{emptyState}</motion.div>;
  }

  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      className={cn('overflow-x-auto rounded-card border border-border bg-surface shadow-card', className)}
    >
      <table className="w-full min-w-[480px] border-collapse text-sm">
        <thead>
          <tr className="border-b border-border bg-surface-muted">
            {columns.map((col) => (
              <th
                key={col.key}
                className={cn(
                  'px-4 py-3 text-left text-label-caps uppercase text-text-secondary',
                  col.className
                )}
              >
                {col.header}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row, i) => (
            <motion.tr
              key={getRowKey(row, i)}
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              transition={{ delay: i * 0.03 }}
              onClick={onRowClick ? () => onRowClick(row) : undefined}
              className={cn(
                'border-b border-border last:border-0',
                onRowClick && 'cursor-pointer transition-colors hover:bg-surface-muted'
              )}
            >
              {columns.map((col) => (
                <td key={col.key} className={cn('px-4 py-3 text-text-primary', col.className)}>
                  {col.render
                    ? col.render(row)
                    : String((row as Record<string, unknown>)[col.key] ?? '')}
                </td>
              ))}
            </motion.tr>
          ))}
        </tbody>
      </table>
    </motion.div>
  );
}
