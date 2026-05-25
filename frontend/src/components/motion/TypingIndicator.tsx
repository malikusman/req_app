import { motion, useReducedMotion } from 'motion/react';
import { cn } from '../../lib/cn';

export function TypingIndicator({ className }: { className?: string }) {
  const reduced = useReducedMotion();

  if (reduced) {
    return (
      <p className={cn('text-xs text-text-secondary', className)} role="status">
        Typing…
      </p>
    );
  }

  return (
    <motion.div
      initial={{ opacity: 0, y: 6 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -4 }}
      className={cn('flex justify-start', className)}
      role="status"
      aria-label="Assistant is typing"
    >
      <div className="flex items-center gap-1 rounded-card border border-border bg-surface-muted px-4 py-3">
        {[0, 1, 2].map((i) => (
          <motion.span
            key={i}
            className="h-2 w-2 rounded-full bg-text-secondary"
            animate={{ y: [0, -5, 0], opacity: [0.4, 1, 0.4] }}
            transition={{
              duration: 0.55,
              repeat: Infinity,
              delay: i * 0.12,
              ease: 'easeInOut',
            }}
          />
        ))}
      </div>
    </motion.div>
  );
}
