import { type SelectHTMLAttributes, useId } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { ChevronDown } from 'lucide-react';
import { cn } from '../../lib/cn';

export type SelectOption = { value: string; label: string };

export function Select({
  label,
  options,
  error,
  className,
  id: idProp,
  ...props
}: Omit<SelectHTMLAttributes<HTMLSelectElement>, 'children'> & {
  label?: string;
  options: SelectOption[];
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
      <div className="relative">
        <select
          id={id}
          className={cn(
            'h-10 w-full appearance-none rounded-button border border-border bg-surface pl-3 pr-9 text-sm text-text-primary transition-colors focus:border-accent focus:outline-none focus:ring-2 focus:ring-accent-muted',
            error && 'border-status-error focus:border-status-error focus:ring-status-errorBg',
            className
          )}
          aria-invalid={error ? true : undefined}
          aria-describedby={error ? `${id}-error` : undefined}
          {...props}
        >
          {options.map((opt) => (
            <option key={opt.value} value={opt.value}>
              {opt.label}
            </option>
          ))}
        </select>
        <ChevronDown className="pointer-events-none absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 text-text-secondary" />
      </div>
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
