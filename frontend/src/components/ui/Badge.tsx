import { type ReactNode } from 'react';
import { motion } from 'motion/react';
import { cn } from '../../lib/cn';

type Variant = 'success' | 'warning' | 'error' | 'info' | 'neutral';

const variants: Record<Variant, string> = {
  success: 'bg-status-successBg text-status-success',
  warning: 'bg-status-warningBg text-status-warning',
  error: 'bg-status-errorBg text-status-error',
  info: 'bg-status-infoBg text-status-info',
  neutral: 'bg-status-neutralBg text-status-neutral',
};

export function Badge({
  variant = 'neutral',
  children,
  className,
}: {
  variant?: Variant;
  children: ReactNode;
  className?: string;
}) {
  return (
    <motion.span
      initial={{ opacity: 0, scale: 0.95 }}
      animate={{ opacity: 1, scale: 1 }}
      transition={{ duration: 0.15 }}
      className={cn(
        'inline-flex items-center rounded-badge px-2.5 py-0.5 text-xs font-medium',
        variants[variant],
        className
      )}
    >
      {children}
    </motion.span>
  );
}
