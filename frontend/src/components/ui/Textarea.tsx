import { type TextareaHTMLAttributes, type ReactNode, useId } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { cn } from '../../lib/cn';

export function Textarea({
  label,
  error,
  className,
  id: idProp,
  ...props
}: TextareaHTMLAttributes<HTMLTextAreaElement> & {
  label?: ReactNode;
  error?: string;
  className?: string;
}) {
  const generatedId = useId();
  const id = idProp ?? generatedId;

  return (
    <motion.div className="flex flex-col gap-1.5" layout>
      {label && (
        <label htmlFor={id} className="text-sm font-medium text-text-primary">
          {label}
        </label>
      )}
      <textarea
        id={id}
        className={cn(
          'min-h-[100px] w-full resize-y rounded-button border border-border bg-white px-3 py-2 text-sm text-text-primary placeholder:text-text-secondary transition-colors focus:border-accent focus:outline-none focus:ring-2 focus:ring-accent-muted',
          error && 'border-status-error focus:border-status-error focus:ring-status-errorBg',
          className
        )}
        aria-invalid={error ? true : undefined}
        aria-describedby={error ? `${id}-error` : undefined}
        {...props}
      />
      <AnimatePresence>
        {error && (
          <motion.span
            id={`${id}-error`}
            initial={{ opacity: 0, y: -4 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -4 }}
            className="text-xs text-status-error"
          >
            {error}
          </motion.span>
        )}
      </AnimatePresence>
    </motion.div>
  );
}
