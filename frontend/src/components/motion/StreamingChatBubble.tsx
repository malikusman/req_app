import { type ReactNode } from 'react';
import { motion, useReducedMotion } from 'motion/react';
import { cn } from '../../lib/cn';
import { messageBubble, transition } from '../../lib/motion';
import { StreamingText } from './StreamingText';

function formatTime(ts: string | Date) {
  const d = typeof ts === 'string' ? new Date(ts) : ts;
  return d.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' });
}

/** Assistant / inbound bubble with optional live token streaming. */
export function StreamingChatBubble({
  body,
  timestamp,
  isStreaming = false,
  meta,
  className,
  variant = 'inbound',
}: {
  body: string;
  timestamp: string | Date;
  isStreaming?: boolean;
  meta?: ReactNode;
  className?: string;
  variant?: 'inbound' | 'outbound';
}) {
  const reduced = useReducedMotion();
  const outbound = variant === 'outbound';

  const bubble = (
    <div
      className={cn(
        'rounded-card px-4 py-2.5 text-sm',
        outbound
          ? 'bg-accent text-white rounded-br-sm'
          : 'border border-border bg-surface-muted text-text-primary rounded-bl-sm'
      )}
    >
      {outbound ? (
        <p className="m-0 whitespace-pre-wrap">{body}</p>
      ) : (
        <StreamingText text={body} isStreaming={isStreaming} className="m-0 block" />
      )}
    </div>
  );

  const row = (
    <>
      {meta}
      <div className={cn('flex max-w-[85%]', outbound ? 'ml-auto justify-end' : 'justify-start')}>
        <div>
          {bubble}
          <span
            className={cn(
              'mt-1 block text-xs text-text-secondary',
              outbound ? 'text-right' : 'text-left'
            )}
          >
            {formatTime(timestamp)}
            {isStreaming && (
              <span className="ml-2 text-accent" role="status">
                · streaming
              </span>
            )}
          </span>
        </div>
      </div>
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
