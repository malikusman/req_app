import { motion } from 'motion/react';
import { cn } from '../../lib/cn';

export type TimelineEvent = {
  id: string;
  title: string;
  summary?: string;
  occurredAt: string | Date;
};

function formatDate(d: string | Date) {
  const date = typeof d === 'string' ? new Date(d) : d;
  return date.toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}

export function Timeline({
  events,
  className,
}: {
  events: TimelineEvent[];
  className?: string;
}) {
  return (
    <motion.ol className={cn('relative space-y-0', className)} initial="hidden" animate="visible">
      {events.map((event, i) => (
        <motion.li
          key={event.id}
          initial={{ opacity: 0, x: -8 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ delay: i * 0.06 }}
          className="relative flex gap-4 pb-8 last:pb-0"
        >
          {i < events.length - 1 && (
            <span
              className="absolute left-[7px] top-4 h-[calc(100%-8px)] w-px bg-border"
              aria-hidden
            />
          )}
          <motion.span
            className="relative z-10 mt-1.5 h-3.5 w-3.5 shrink-0 rounded-full border-2 border-accent bg-surface"
            layout
          />
          <div className="min-w-0 flex-1 pt-0">
            <div className="flex flex-wrap items-baseline justify-between gap-2">
              <h4 className="text-sm font-semibold text-text-primary">{event.title}</h4>
              <time className="text-xs text-text-secondary">{formatDate(event.occurredAt)}</time>
            </div>
            {event.summary && (
              <p className="mt-1 text-sm text-text-secondary">{event.summary}</p>
            )}
          </div>
        </motion.li>
      ))}
    </motion.ol>
  );
}
