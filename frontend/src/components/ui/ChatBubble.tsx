import { type ReactNode } from 'react';
import { motion, useReducedMotion } from 'motion/react';
import { cn } from '../../lib/cn';
import { messageBubble, transition } from '../../lib/motion';

type Direction = 'inbound' | 'outbound';

function formatTime(ts: string | Date) {
  const d = typeof ts === 'string' ? new Date(ts) : ts;
  if (Number.isNaN(d.getTime())) return '';
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
  const timeLabel = formatTime(timestamp);

  const content = (
    <div
      className={cn(
        'flex w-full',
        outbound ? 'justify-end' : 'justify-start'
      )}
    >
      <div
        className={cn(
          'flex min-w-0 max-w-[min(85%,28rem)] flex-col gap-2',
          outbound ? 'items-end' : 'items-start'
        )}
      >
        {meta ? <div className="w-full min-w-0">{meta}</div> : null}
        <div
          className={cn(
            'rounded-lg px-4 py-2.5 text-sm shadow-sm',
            outbound
              ? 'rounded-br-sm bg-primary text-primary-foreground'
              : 'rounded-bl-sm border border-border bg-card text-foreground'
          )}
        >
          <p className="m-0 whitespace-pre-wrap break-words">{body}</p>
        </div>
        {timeLabel ? (
          <span
            className={cn(
              'text-xs tabular-nums text-muted-foreground',
              outbound ? 'text-right' : 'text-left'
            )}
          >
            {timeLabel}
          </span>
        ) : null}
      </div>
    </div>
  );

  if (reduced) {
    return <div className={className}>{content}</div>;
  }

  return (
    <motion.div
      initial="hidden"
      animate="visible"
      exit="exit"
      variants={messageBubble}
      transition={transition.fast}
      className={className}
    >
      {content}
    </motion.div>
  );
}
