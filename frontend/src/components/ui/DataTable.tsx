import { type ReactNode } from 'react';
import { motion, useReducedMotion } from 'motion/react';
import { cn } from '../../lib/cn';
import { fadeUp, stagger, transition } from '../../lib/motion';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/shadcn/table';
import { Card } from '@/components/shadcn/card';
import { Skeleton } from '@/components/shadcn/skeleton';
import { EmptyState } from './EmptyState';

export type Column<T> = {
  key: string;
  header: string;
  render?: (row: T) => ReactNode;
  className?: string;
  /** Hide this column from the mobile card layout (e.g. redundant action column). */
  hideOnMobile?: boolean;
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
  const reduced = useReducedMotion();

  if (loading) {
    return (
      <Card className={cn('overflow-hidden p-0', className)}>
        <div className="divide-y">
          {Array.from({ length: 5 }).map((_, i) => (
            <div key={i} className="flex gap-4 px-4 py-3">
              <Skeleton className="h-4 w-full" />
            </div>
          ))}
        </div>
      </Card>
    );
  }

  const emptyContent =
    emptyState ?? (
      <EmptyState title="No data" description="Nothing to show yet." className="py-8" />
    );

  const cellValue = (col: Column<T>, row: T) =>
    col.render ? col.render(row) : String((row as Record<string, unknown>)[col.key] ?? '');

  const mobileColumns = columns.filter((col) => !col.hideOnMobile && col.header);

  return (
    <Card className={cn('overflow-hidden p-0', className)}>
      {/* Mobile: stacked cards — avoids sideways-scrolling desktop tables */}
      <div className="divide-y divide-border md:hidden">
        {rows.length === 0 ? (
          <div className="p-4">{emptyContent}</div>
        ) : (
          rows.map((row, i) => {
            const rowKey = getRowKey(row, i);
            const clickable = Boolean(onRowClick);
            return (
              <div
                key={rowKey}
                role={clickable ? 'button' : undefined}
                tabIndex={clickable ? 0 : undefined}
                onClick={onRowClick ? () => onRowClick(row) : undefined}
                onKeyDown={
                  onRowClick
                    ? (e) => {
                        if (e.key === 'Enter' || e.key === ' ') {
                          e.preventDefault();
                          onRowClick(row);
                        }
                      }
                    : undefined
                }
                className={cn(
                  'space-y-2 px-4 py-3 text-sm',
                  clickable && 'cursor-pointer active:bg-muted/60'
                )}
              >
                {mobileColumns.map((col) => (
                  <div key={col.key} className="min-w-0">
                    <div className="text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">
                      {col.header}
                    </div>
                    <div className="mt-0.5 break-words text-foreground">{cellValue(col, row)}</div>
                  </div>
                ))}
                {/* Columns with empty headers (usually actions) still render once at the bottom */}
                {columns
                  .filter((col) => !col.hideOnMobile && !col.header)
                  .map((col) => (
                    <div key={col.key} className="pt-1" onClick={(e) => e.stopPropagation()}>
                      {cellValue(col, row)}
                    </div>
                  ))}
              </div>
            );
          })
        )}
      </div>

      {/* Desktop table */}
      <div className="hidden md:block">
        <Table>
          <TableHeader>
            <TableRow className="hover:bg-transparent">
              {columns.map((col) => (
                <TableHead key={col.key} className={col.className}>
                  {col.header}
                </TableHead>
              ))}
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.length === 0 ? (
              <TableRow className="hover:bg-transparent">
                <TableCell colSpan={columns.length} className="p-0">
                  {emptyContent}
                </TableCell>
              </TableRow>
            ) : (
              rows.map((row, i) => {
                const rowKey = getRowKey(row, i);
                const clickable = Boolean(onRowClick);

                if (reduced) {
                  return (
                    <TableRow
                      key={rowKey}
                      onClick={onRowClick ? () => onRowClick(row) : undefined}
                      className={cn(clickable && 'cursor-pointer')}
                    >
                      {columns.map((col) => (
                        <TableCell key={col.key} className={col.className}>
                          {cellValue(col, row)}
                        </TableCell>
                      ))}
                    </TableRow>
                  );
                }

                return (
                  <motion.tr
                    key={rowKey}
                    onClick={onRowClick ? () => onRowClick(row) : undefined}
                    initial="hidden"
                    animate="visible"
                    variants={fadeUp}
                    transition={{ ...transition.fast, delay: i * stagger.tight }}
                    className={cn(
                      'border-b transition-colors hover:bg-muted/50 data-[state=selected]:bg-muted',
                      clickable && 'cursor-pointer'
                    )}
                  >
                    {columns.map((col) => (
                      <TableCell key={col.key} className={col.className}>
                        {cellValue(col, row)}
                      </TableCell>
                    ))}
                  </motion.tr>
                );
              })
            )}
          </TableBody>
        </Table>
      </div>
    </Card>
  );
}
