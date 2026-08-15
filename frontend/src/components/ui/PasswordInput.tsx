import { type InputHTMLAttributes, useId, useState } from 'react';
import { AnimatePresence, motion } from 'motion/react';
import { Eye, EyeOff } from 'lucide-react';
import { Input as ShadcnInput } from '@/components/shadcn/input';
import { Label } from '@/components/shadcn/label';
import { cn } from '../../lib/cn';

export function PasswordInput({
  label,
  error,
  className,
  id: idProp,
  autoComplete,
  ...props
}: Omit<InputHTMLAttributes<HTMLInputElement>, 'type'> & {
  label?: string;
  error?: string;
  className?: string;
}) {
  const generatedId = useId();
  const id = idProp ?? generatedId;
  const [visible, setVisible] = useState(false);

  return (
    <div className="flex flex-col gap-1.5">
      {label && <Label htmlFor={id}>{label}</Label>}
      <div className="relative">
        <ShadcnInput
          id={id}
          type={visible ? 'text' : 'password'}
          autoComplete={autoComplete}
          className={cn(
            'pr-10',
            error && 'border-destructive focus-visible:ring-destructive',
            className
          )}
          aria-invalid={error ? true : undefined}
          aria-describedby={error ? `${id}-error` : undefined}
          {...props}
        />
        <button
          type="button"
          onClick={() => setVisible((v) => !v)}
          className="absolute right-2 top-1/2 -translate-y-1/2 rounded-md p-1 text-muted-foreground hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          aria-label={visible ? 'Hide password' : 'Show password'}
          aria-pressed={visible}
        >
          {visible ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
        </button>
      </div>
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
