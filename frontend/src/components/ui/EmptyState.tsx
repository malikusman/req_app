import { type LucideIcon } from 'lucide-react';
import { motion } from 'motion/react';
import { cn } from '../../lib/cn';
import { Button } from './Button';

export function EmptyState({
  icon: Icon,
  title,
  description,
  action,
  secondaryAction,
  className,
}: {
  icon?: LucideIcon;
  title: string;
  description?: string;
  action?: { label: string; onClick: () => void };
  secondaryAction?: { label: string; onClick: () => void };
  className?: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.25 }}
      className={cn('flex flex-col items-center justify-center px-6 py-16 text-center', className)}
    >
      {Icon && (
        <motion.div
          initial={{ scale: 0.9 }}
          animate={{ scale: 1 }}
          transition={{ delay: 0.05 }}
          className="mb-4 flex h-14 w-14 items-center justify-center rounded-full bg-muted"
        >
          <Icon className="h-7 w-7 text-muted-foreground" strokeWidth={1.5} />
        </motion.div>
      )}
      <h3 className="text-section-title text-foreground">{title}</h3>
      {description && (
        <p className="mt-2 max-w-sm text-sm text-muted-foreground">{description}</p>
      )}
      {(action || secondaryAction) && (
        <motion.div className="mt-6 flex flex-wrap items-center justify-center gap-3">
          {action && <Button onClick={action.onClick}>{action.label}</Button>}
          {secondaryAction && (
            <Button variant="secondary" onClick={secondaryAction.onClick}>
              {secondaryAction.label}
            </Button>
          )}
        </motion.div>
      )}
    </motion.div>
  );
}
