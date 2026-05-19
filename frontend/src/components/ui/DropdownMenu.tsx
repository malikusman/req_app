import { useEffect, useRef, useState, type ReactNode } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { MoreHorizontal } from 'lucide-react';
import { cn } from '../../lib/cn';

export type DropdownMenuItem = {
  label: string;
  onClick: () => void;
  danger?: boolean;
  disabled?: boolean;
};

export function DropdownMenu({
  items,
  trigger,
  align = 'right',
  className,
}: {
  items: DropdownMenuItem[];
  trigger?: ReactNode;
  align?: 'left' | 'right';
  className?: string;
}) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const onClickOutside = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        setOpen(false);
      }
    };
    document.addEventListener('mousedown', onClickOutside);
    return () => document.removeEventListener('mousedown', onClickOutside);
  }, [open]);

  return (
    <motion.div ref={ref} className={cn('relative inline-block', className)}>
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        className="rounded-button p-1.5 text-text-secondary transition-colors hover:bg-surface-muted hover:text-text-primary"
        aria-expanded={open}
        aria-haspopup="menu"
      >
        {trigger ?? <MoreHorizontal className="h-4 w-4" />}
      </button>
      <AnimatePresence>
        {open && (
          <motion.div
            role="menu"
            initial={{ opacity: 0, scale: 0.95, y: -4 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.95, y: -4 }}
            transition={{ duration: 0.15 }}
            className={cn(
              'absolute z-50 mt-1 min-w-[160px] overflow-hidden rounded-card border border-border bg-surface py-1 shadow-modal',
              align === 'right' ? 'right-0' : 'left-0'
            )}
          >
            {items.map((item) => (
              <button
                key={item.label}
                type="button"
                role="menuitem"
                disabled={item.disabled}
                onClick={() => {
                  if (!item.disabled) {
                    item.onClick();
                    setOpen(false);
                  }
                }}
                className={cn(
                  'block w-full px-3 py-2 text-left text-sm transition-colors disabled:opacity-50',
                  item.danger
                    ? 'text-status-error hover:bg-status-errorBg'
                    : 'text-text-primary hover:bg-surface-muted'
                )}
              >
                {item.label}
              </button>
            ))}
          </motion.div>
        )}
      </AnimatePresence>
    </motion.div>
  );
}
