import { motion, useReducedMotion } from 'motion/react';
import { cn } from '../../lib/cn';

export function StreamingText({
  text,
  isStreaming = false,
  className,
}: {
  text: string;
  isStreaming?: boolean;
  className?: string;
}) {
  const reduced = useReducedMotion();

  return (
    <span className={cn('inline', className)}>
      <span className="whitespace-pre-wrap">{text}</span>
      {isStreaming && !reduced && (
        <motion.span
          className="ml-0.5 inline-block h-[1em] w-0.5 translate-y-px bg-current align-middle"
          animate={{ opacity: [1, 0.2, 1] }}
          transition={{ duration: 0.85, repeat: Infinity, ease: 'easeInOut' }}
          aria-hidden
        />
      )}
    </span>
  );
}
