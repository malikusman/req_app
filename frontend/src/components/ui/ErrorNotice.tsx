import type { ReactNode } from 'react';
import { AlertTriangle } from 'lucide-react';
import { Button } from './Button';
import { cn } from '../../lib/cn';

/**
 * One way to show a failure that a person can act on.
 *
 * This markup was hand-repeated across thirteen screens with small drifts —
 * some carried a Retry, some did not, some were a bare red sentence — so the
 * same class of failure looked different depending on where you hit it. The
 * rule: anything tied to a region or a field is shown inline, here; the toast
 * is for the result of an action that already moved the user somewhere else.
 *
 * `role="alert"` so a screen reader announces it rather than leaving the user
 * waiting on content that will never arrive.
 */
export function ErrorNotice({
  message,
  onRetry,
  retryLabel = 'Retry',
  action,
  className,
}: {
  message: string;
  onRetry?: () => void;
  retryLabel?: string;
  action?: ReactNode;
  className?: string;
}) {
  return (
    <div
      role="alert"
      className={cn(
        'flex flex-wrap items-center justify-between gap-3 rounded-button border border-status-error/30 bg-status-errorBg px-4 py-3 text-sm text-status-error',
        className
      )}
    >
      <span className="flex min-w-0 items-start gap-2">
        <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" aria-hidden />
        <span className="min-w-0">{message}</span>
      </span>
      {action ??
        (onRetry ? (
          <Button size="sm" variant="secondary" onClick={onRetry}>
            {retryLabel}
          </Button>
        ) : null)}
    </div>
  );
}
