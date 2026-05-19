import { motion } from 'motion/react';
import { cn } from '../../lib/cn';

export type TabItem = { value: string; label: string };

export function Tabs({
  tabs,
  value,
  onChange,
  className,
}: {
  tabs: TabItem[];
  value: string;
  onChange: (value: string) => void;
  className?: string;
}) {
  return (
    <div className={cn('border-b border-border', className)} role="tablist">
      <motion.div className="flex gap-1">
        {tabs.map((tab) => {
          const active = tab.value === value;
          return (
            <button
              key={tab.value}
              type="button"
              role="tab"
              aria-selected={active}
              onClick={() => onChange(tab.value)}
              className={cn(
                'relative px-4 py-2.5 text-sm font-medium transition-colors',
                active ? 'text-accent' : 'text-text-secondary hover:text-text-primary'
              )}
            >
              {tab.label}
              {active && (
                <motion.span
                  layoutId="tab-indicator"
                  className="absolute bottom-0 left-0 right-0 h-0.5 bg-accent"
                  transition={{ type: 'spring', stiffness: 400, damping: 30 }}
                />
              )}
            </button>
          );
        })}
      </motion.div>
    </div>
  );
}
