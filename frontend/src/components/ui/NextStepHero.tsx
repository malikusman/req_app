import { type ReactNode } from 'react';
import { Link } from 'react-router-dom';
import { ArrowRight } from 'lucide-react';
import { Button } from './Button';
import { ReadinessGauge } from './ReadinessGauge';
import { cn } from '../../lib/cn';

export type HeroAction = {
  label: string;
  to?: string;
  onClick?: () => void;
};

/**
 * Elevated, state-aware "do this next" card — the single primary action on a
 * guided dashboard. Generic + prop-driven so consultant/admin homes can reuse it.
 */
export function NextStepHero({
  eyebrow = 'Do this next',
  title,
  description,
  primaryAction,
  secondaryAction,
  readiness,
  className,
}: {
  eyebrow?: string;
  title: string;
  description?: ReactNode;
  primaryAction: HeroAction;
  secondaryAction?: HeroAction;
  readiness?: { percent: number; label?: string };
  className?: string;
}) {
  return (
    <section
      className={cn(
        'flex flex-col items-start gap-6 rounded-card border border-accent/40 bg-accent-muted p-6 shadow-hero-mockup sm:flex-row sm:items-center sm:gap-8',
        className
      )}
    >
      <div className="min-w-0 flex-1">
        <p className="text-label-caps uppercase tracking-wider text-accent-hover">{eyebrow}</p>
        <h2 className="mt-2 font-display text-2xl font-semibold leading-tight text-foreground text-balance">
          {title}
        </h2>
        {description && (
          <div className="mt-2 max-w-[56ch] text-sm leading-relaxed text-foreground/80">{description}</div>
        )}
        <div className="mt-5 flex flex-col gap-3 sm:flex-row sm:flex-wrap">
          <HeroButton action={primaryAction} variant="primary" withArrow className="w-full sm:w-auto" />
          {secondaryAction && (
            <HeroButton action={secondaryAction} variant="secondary" className="w-full sm:w-auto" />
          )}
        </div>
      </div>
      {readiness && (
        <div className="mx-auto shrink-0 sm:mx-0">
          <ReadinessGauge score={readiness.percent} breakdown={{}} compact label={readiness.label ?? 'Ready'} />
        </div>
      )}
    </section>
  );
}

function HeroButton({
  action,
  variant,
  withArrow,
  className,
}: {
  action: HeroAction;
  variant: 'primary' | 'secondary';
  withArrow?: boolean;
  className?: string;
}) {
  const button = (
    <Button
      variant={variant}
      className={cn('rounded-badge', className)}
      onClick={action.onClick}
    >
      {action.label}
      {withArrow && <ArrowRight className="h-4 w-4" />}
    </Button>
  );
  if (action.to) {
    return (
      <Link to={action.to} className={cn('inline-flex', className?.includes('w-full') && 'w-full')}>
        {button}
      </Link>
    );
  }
  return button;
}
