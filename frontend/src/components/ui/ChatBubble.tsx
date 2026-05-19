import { motion } from 'motion/react';
import { cn } from '../../lib/cn';

type Direction = 'inbound' | 'outbound';

function formatTime(ts: string | Date) {
  const d = typeof ts === 'string' ? new Date(ts) : ts;
  return d.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' });
}

export function ChatBubble({
  direction,
  body,
  timestamp,
  className,
}: {
  direction: Direction;
  body: string;
  timestamp: string | Date;
  className?: string;
}) {
  const outbound = direction === 'outbound';

  return (
    <motion.div
      initial={{ opacity: 0, y: 6 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.2 }}
      className={cn('flex', outbound ? 'justify-end' : 'justify-start', className)}
    >
      <div className={cn('max-w-[85%]', outbound ? 'items-end' : 'items-start')}>
        <motion.div
          className={cn(
            'rounded-card px-4 py-2.5 text-sm',
            outbound
              ? 'bg-accent text-white rounded-br-sm'
              : 'border border-border bg-surface-muted text-text-primary rounded-bl-sm'
          )}
        >
          <p className="m-0 whitespace-pre-wrap">{body}</p>
        </motion.div>
        <span
          className={cn(
            'mt-1 block text-xs text-text-secondary',
            outbound ? 'text-right' : 'text-left'
          )}
        >
          {formatTime(timestamp)}
        </span>
      </div>
    </motion.div>
  );
}
