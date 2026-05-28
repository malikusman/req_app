import { type InputHTMLAttributes } from 'react';
import { motion } from 'motion/react';
import { Search, X } from 'lucide-react';
import { cn } from '../../lib/cn';

export function SearchInput({
  value,
  onChange,
  onClear,
  placeholder = 'Search…',
  className,
  ...props
}: Omit<InputHTMLAttributes<HTMLInputElement>, 'type'> & {
  onClear?: () => void;
}) {
  const showClear = onClear && value && String(value).length > 0;

  return (
    <motion.div
      className={cn('relative', className)}
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
    >
      <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-text-secondary" />
      <input
        type="search"
        value={value}
        onChange={onChange}
        placeholder={placeholder}
        className="h-10 w-full rounded-button border border-border bg-surface pl-9 pr-9 text-sm text-text-primary placeholder:text-text-secondary focus:border-accent focus:outline-none focus:ring-2 focus:ring-accent-muted"
        {...props}
      />
      {showClear && (
        <motion.button
          type="button"
          initial={{ opacity: 0, scale: 0.8 }}
          animate={{ opacity: 1, scale: 1 }}
          onClick={onClear}
          className="absolute right-2 top-1/2 -translate-y-1/2 rounded p-1 text-text-secondary hover:bg-surface-muted hover:text-text-primary"
          aria-label="Clear search"
        >
          <X className="h-4 w-4" />
        </motion.button>
      )}
    </motion.div>
  );
}
