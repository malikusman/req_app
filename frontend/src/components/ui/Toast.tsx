import { motion } from 'motion/react';
import { CheckCircle2, AlertCircle, Info, X, AlertTriangle } from 'lucide-react';
import { cn } from '../../lib/cn';

export type ToastVariant = 'success' | 'error' | 'warning' | 'info';

export type ToastItem = {
  id: string;
  title: string;
  description?: string;
  variant?: ToastVariant;
};

const icons: Record<ToastVariant, typeof CheckCircle2> = {
  success: CheckCircle2,
  error: AlertCircle,
  warning: AlertTriangle,
  info: Info,
};

const styles: Record<ToastVariant, string> = {
  success: 'border-status-success/30 bg-status-successBg',
  error: 'border-status-error/30 bg-status-errorBg',
  warning: 'border-status-warning/30 bg-status-warningBg',
  info: 'border-status-info/30 bg-status-infoBg',
};

const iconColors: Record<ToastVariant, string> = {
  success: 'text-status-success',
  error: 'text-status-error',
  warning: 'text-status-warning',
  info: 'text-status-info',
};

export function Toast({
  toast,
  onDismiss,
}: {
  toast: ToastItem;
  onDismiss: (id: string) => void;
}) {
  const variant = toast.variant ?? 'info';
  const Icon = icons[variant];

  return (
    <motion.div
      layout
      initial={{ opacity: 0, x: 48 }}
      animate={{ opacity: 1, x: 0 }}
      exit={{ opacity: 0, x: 48 }}
      transition={{ duration: 0.2 }}
      className={cn(
        'pointer-events-auto flex w-80 items-start gap-3 rounded-card border p-4 shadow-modal',
        styles[variant]
      )}
      role="alert"
    >
      <Icon className={cn('h-5 w-5 shrink-0', iconColors[variant])} />
      <motion.div className="min-w-0 flex-1">
        <p className="text-sm font-semibold text-text-primary">{toast.title}</p>
        {toast.description && (
          <p className="mt-0.5 text-xs text-text-secondary">{toast.description}</p>
        )}
      </motion.div>
      <button
        type="button"
        onClick={() => onDismiss(toast.id)}
        className="shrink-0 rounded p-0.5 text-text-secondary hover:text-text-primary"
        aria-label="Dismiss"
      >
        <X className="h-4 w-4" />
      </button>
    </motion.div>
  );
}
