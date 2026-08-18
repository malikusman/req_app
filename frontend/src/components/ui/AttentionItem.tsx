import { type ReactNode } from 'react';
import { Link } from 'react-router-dom';
import { cn } from '../../lib/cn';

export type AttentionItemData = {
  tone: 'attention' | 'neutral';
  icon: ReactNode;
  title: string;
  detail?: string;
  /** A link the whole row routes to. */
  action?: { label: string; to: string };
  /** When there is nothing to do, show a muted label instead of an action. */
  optionalLabel?: string;
};

/**
 * A ranked "also waiting for you" row. Amber tint for attention, muted for neutral.
 */
export function AttentionItem({ tone, icon, title, detail, action, optionalLabel }: AttentionItemData) {
  const attention = tone === 'attention';
  const inner = (
    <div
      className={cn(
        'flex items-center gap-3 rounded-md border p-3.5 transition-colors',
        attention
          ? 'border-status-warning/30 bg-status-warningBg'
          : 'border-border bg-card',
        action && 'hover:border-primary/40'
      )}
    >
      <span
        className={cn(
          'flex h-9 w-9 shrink-0 items-center justify-center rounded-md',
          attention ? 'bg-status-warning/15 text-status-warning' : 'bg-muted text-muted-foreground'
        )}
      >
        {icon}
      </span>
      <div className="min-w-0 flex-1">
        <p className="m-0 truncate text-sm font-semibold text-foreground">{title}</p>
        {detail && <p className="m-0 mt-0.5 truncate text-xs text-muted-foreground">{detail}</p>}
      </div>
      {action ? (
        <span className="ml-auto shrink-0 whitespace-nowrap text-sm font-semibold text-accent-hover">
          {action.label} →
        </span>
      ) : optionalLabel ? (
        <span className="ml-auto shrink-0 text-label-caps uppercase text-muted-foreground">{optionalLabel}</span>
      ) : null}
    </div>
  );

  if (action) {
    return (
      <Link to={action.to} className="block rounded-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
        {inner}
      </Link>
    );
  }
  return inner;
}

/** Convenience list wrapper — 1 column on mobile, 2-up on wider screens. */
export function AttentionList({ items, className }: { items: AttentionItemData[]; className?: string }) {
  if (items.length === 0) return null;
  return (
    <div className={cn('grid gap-3 sm:grid-cols-2', className)}>
      {items.map((item, i) => (
        <AttentionItem key={`${item.title}-${i}`} {...item} />
      ))}
    </div>
  );
}
