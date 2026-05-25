import { type ReactNode } from 'react';
import { motion, useReducedMotion } from 'motion/react';
import { cn } from '../../lib/cn';
import { messageBubble, transition } from '../../lib/motion';

type Direction = 'inbound' | 'outbound';

function formatTime(ts: string | Date) {
  const d = typeof ts === 'string' ? new Date(ts) : ts;
  return d.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' });
}

export function ChatBubble({
  direction,
  body,
  timestamp,
  meta,
  className,
}: {
  direction: Direction;
  body: string;
  timestamp: string | Date;
  meta?: ReactNode;
  className?: string;
}) {
  const outbound = direction === 'outbound';
  const reduced = useReducedMotion();

  const bubble = (
    <div className={cn('max-w-[85%]', outbound ? 'items-end' : 'items-start')}>
      <div
        className={cn(
          'rounded-card px-4 py-2.5 text-sm',
          outbound
            ? 'bg-accent text-white rounded-br-sm'
            : 'border border-border bg-surface-muted text-text-primary rounded-bl-sm'
        )}
      >
        <p className="m-0 whitespace-pre-wrap">{body}</p>
      </div>
      <span
        className={cn(
          'mt-1 block text-xs text-text-secondary',
          outbound ? 'text-right' : 'text-left'
        )}
      >
        {formatTime(timestamp)}
      </span>
    </div>
  );

  const row = (
    <>
      {meta}
      <div className={cn('flex', outbound ? 'justify-end' : 'justify-start')}>{bubble}</div>
    </>
  );

  if (reduced) {
    return <div className={className}>{row}</div>;
  }

  return (
    <motion.div
      layout
      initial="hidden"
      animate="visible"
      exit="exit"
      variants={messageBubble}
      transition={transition.fast}
      className={className}
    >
      {row}
    </motion.div>
  );
}
