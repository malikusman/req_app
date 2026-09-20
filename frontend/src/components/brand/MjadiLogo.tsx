import { cn } from '../../lib/cn';

/**
 * The mark: an aiming reticle — a ring with the sight open at the top right,
 * and a dot dead centre.
 *
 * Mjadi is Emirati dialect for someone concentrating hard on a target, so the
 * mark is that and nothing else. No robots, no brains, no neural nets. The gap
 * in the ring is what keeps it from reading as a generic bullseye, and it holds
 * its shape down to 16px because it is two shapes and one weight.
 *
 * Draws in `currentColor`, so it takes the colour of whatever it sits in.
 */
export function MjadiMark({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 32 32"
      fill="none"
      role="img"
      aria-label="Mjadi"
      className={cn('h-8 w-8 text-primary', className)}
    >
      <path
        d="M18.08 4.18A12 12 0 1 0 26.39 10"
        stroke="currentColor"
        strokeWidth="2.5"
        strokeLinecap="round"
      />
      <circle cx="16" cy="16" r="4" fill="currentColor" />
    </svg>
  );
}

/** The mark with the name beside it, for navigation and sign-in. */
export function MjadiLogo({
  className,
  wordmarkClassName,
}: {
  className?: string;
  wordmarkClassName?: string;
}) {
  return (
    <span className={cn('inline-flex items-center gap-2.5', className)}>
      <MjadiMark />
      <span className={cn('font-display text-xl font-semibold tracking-tight', wordmarkClassName)}>
        Mjadi
      </span>
    </span>
  );
}
