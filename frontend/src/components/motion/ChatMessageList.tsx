import { useEffect, useRef } from 'react';
import { AnimatePresence } from 'motion/react';
import { ChatBubble } from '../ui/ChatBubble';
import { cn } from '../../lib/cn';
import { TypingIndicator } from './TypingIndicator';

export type ChatMessageItem = {
  id: string | number;
  direction: 'inbound' | 'outbound';
  body: string;
  timestamp: string | Date;
  meta?: React.ReactNode;
  actions?: React.ReactNode;
};

export function ChatMessageList({
  messages,
  className,
  showTyping = false,
  autoScroll = true,
  highlightedMessageId,
}: {
  messages: ChatMessageItem[];
  className?: string;
  showTyping?: boolean;
  autoScroll?: boolean;
  highlightedMessageId?: string | number | null;
}) {
  const scrollRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!autoScroll || !scrollRef.current) return;
    scrollRef.current.scrollTo({
      top: scrollRef.current.scrollHeight,
      behavior: 'smooth',
    });
  }, [messages.length, showTyping, autoScroll]);

  return (
    <div
      ref={scrollRef}
      className={cn(
        'flex flex-col gap-4 overflow-y-auto overscroll-contain px-1 py-2',
        className
      )}
    >
      <AnimatePresence initial={false} mode="popLayout">
        {messages.map((m) => (
          <div
            key={m.id}
            className={cn(
              'group relative',
              m.direction === 'outbound' ? 'self-end' : 'self-start'
            )}
          >
            <ChatBubble
              direction={m.direction}
              body={m.body}
              timestamp={m.timestamp}
              meta={m.meta}
              className={cn(
                highlightedMessageId != null && m.id === highlightedMessageId && 'rounded-lg ring-2 ring-primary/40'
              )}
            />
            {m.actions && (
              <div className={cn('absolute top-1 opacity-0 transition-opacity group-hover:opacity-100', m.direction === 'outbound' ? 'left-0 -translate-x-full pr-2' : 'right-0 translate-x-full pl-2')}>
                {m.actions}
              </div>
            )}
          </div>
        ))}
      </AnimatePresence>
      {showTyping && (
        <div>
          <TypingIndicator />
        </div>
      )}
    </div>
  );
}
