import { type InputHTMLAttributes, type ReactNode, useId } from 'react';
import { AnimatePresence, motion } from 'motion/react';
import { Input as ShadcnInput } from '@/components/shadcn/input';
import { Label } from '@/components/shadcn/label';
import { cn } from '../../lib/cn';

export function Input({
  label,
  error,
  className,
  id: idProp,
  ...props
}: InputHTMLAttributes<HTMLInputElement> & {
  label?: ReactNode;
  error?: string;
  className?: string;
}) {
  const generatedId = useId();
  const id = idProp ?? generatedId;

  return (
    <div className="flex flex-col gap-1.5">
      {label && <Label htmlFor={id}>{label}</Label>}
      <ShadcnInput
        id={id}
        className={cn(error && 'border-destructive focus-visible:ring-destructive', className)}
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
            className="text-xs text-destructive"
          >
            {error}
          </motion.span>
        )}
      </AnimatePresence>
    </div>
  );
}
