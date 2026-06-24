import { motion } from 'motion/react';
import { cn } from '../../lib/cn';

type Variant = 'text' | 'card' | 'table-row';

export function Skeleton({ variant = 'text', className }: { variant?: Variant; className?: string }) {
  const base = 'animate-pulse rounded bg-muted';

  if (variant === 'card') {
    return (
      <motion.div
        initial={{ opacity: 0.6 }}
        animate={{ opacity: [0.6, 1, 0.6] }}
        transition={{ duration: 1.5, repeat: Infinity }}
        className={cn('rounded-lg border border-border bg-card p-6 shadow-sm', className)}
      >
        <div className={cn(base, 'mb-4 h-4 w-1/3')} />
        <motion.div className={cn(base, 'mb-2 h-3 w-full')} />
        <motion.div className={cn(base, 'h-3 w-2/3')} />
      </motion.div>
    );
  }

  if (variant === 'table-row') {
    return (
      <motion.div
        initial={{ opacity: 0.6 }}
        animate={{ opacity: [0.6, 1, 0.6] }}
        transition={{ duration: 1.5, repeat: Infinity }}
        className={cn('flex items-center gap-4 border-b border-border px-4 py-3', className)}
      >
        <motion.div className={cn(base, 'h-4 w-4 shrink-0 rounded')} />
        <motion.div className={cn(base, 'h-4 flex-1')} />
        <motion.div className={cn(base, 'h-4 w-24')} />
        <motion.div className={cn(base, 'h-4 w-16')} />
      </motion.div>
    );
  }

  return (
    <motion.div
      initial={{ opacity: 0.6 }}
      animate={{ opacity: [0.6, 1, 0.6] }}
      transition={{ duration: 1.5, repeat: Infinity }}
      className={cn(base, 'h-4 w-full', className)}
    />
  );
}
