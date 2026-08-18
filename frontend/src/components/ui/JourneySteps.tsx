import { Check, Star } from 'lucide-react';
import { cn } from '../../lib/cn';

export type JourneyStep = {
  label: string;
  sublabel?: string;
  status: 'done' | 'now' | 'optional' | 'todo';
};

/**
 * Horizontal stepper with a connector line that runs green through completed
 * steps. Scrolls horizontally on narrow screens.
 */
export function JourneySteps({ steps, className }: { steps: JourneyStep[]; className?: string }) {
  return (
    <div className={cn('overflow-x-auto', className)}>
      <ol className="flex min-w-full items-start">
        {steps.map((step, i) => {
          const filled = step.status === 'done' || step.status === 'now';
          return (
            <li
              key={step.label}
              className="relative flex min-w-[84px] flex-1 flex-col items-center gap-2 text-center"
            >
              {i > 0 && (
                <span
                  aria-hidden
                  className={cn(
                    'absolute left-[-50%] right-1/2 top-[13px] h-0.5',
                    filled ? 'bg-primary' : 'bg-border'
                  )}
                />
              )}
              <span
                className={cn(
                  'relative z-10 flex h-7 w-7 items-center justify-center rounded-full text-[11px] font-bold',
                  step.status === 'done' && 'bg-primary text-primary-foreground',
                  step.status === 'now' && 'bg-primary text-primary-foreground ring-4 ring-accent-muted',
                  step.status === 'optional' &&
                    'border border-dashed border-status-warning/50 bg-card text-status-warning',
                  step.status === 'todo' && 'border border-border bg-card text-muted-foreground'
                )}
              >
                {step.status === 'done' ? (
                  <Check className="h-3.5 w-3.5" strokeWidth={3} />
                ) : step.status === 'now' ? (
                  <Star className="h-3.5 w-3.5" fill="currentColor" />
                ) : step.status === 'optional' ? (
                  '○'
                ) : (
                  i + 1
                )}
              </span>
              <span className="px-1">
                <span className="block text-xs font-semibold text-foreground">{step.label}</span>
                {step.sublabel && (
                  <span className="mt-0.5 block text-[11px] text-muted-foreground">{step.sublabel}</span>
                )}
              </span>
            </li>
          );
        })}
      </ol>
    </div>
  );
}
