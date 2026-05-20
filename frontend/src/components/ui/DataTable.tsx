import { type ReactNode } from 'react';
import { cn } from '../../lib/cn';
import { Skeleton } from './Skeleton';
import { EmptyState } from './EmptyState';

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
      <div className={cn('overflow-hidden rounded-card border border-border bg-surface shadow-card', className)}>
        {Array.from({ length: 5 }).map((_, i) => (
          <Skeleton key={i} variant="table-row" />
        ))}
      </div>
    );
  }

  const emptyContent =
    emptyState ?? (
      <EmptyState title="No data" description="Nothing to show yet." className="py-8" />
    );

  return (
    <div className={cn('overflow-x-auto rounded-card border border-border bg-surface shadow-card', className)}>
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
          {rows.length === 0 ? (
            <tr>
              <td colSpan={columns.length} className="p-0">
                {emptyContent}
              </td>
            </tr>
          ) : (
            rows.map((row, i) => (
              <tr
                key={getRowKey(row, i)}
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
              </tr>
            ))
          )}
        </tbody>
      </table>
    </div>
  );
}
