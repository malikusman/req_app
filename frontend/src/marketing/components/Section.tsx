import type { ReactNode } from 'react';
import { ScrollReveal } from '../../components/motion';
import { cn } from '../../lib/cn';

/**
 * The section wrapper every marketing block shares.
 *
 * It used to be copy-pasted into each file, and had drifted: padding was
 * `px-6 md:px-12 py-24 md:py-28` in six sections and `px-5 sm:px-8 py-20` in
 * three, with container widths of 6xl, 5xl, 4xl and 3xl depending on when the
 * file was written. That inconsistency is most of why the page read as a pile
 * of blocks rather than one document.
 *
 * The vertical scale is deliberately tighter than what it replaces —
 * `py-16 sm:py-20 lg:py-24` against the old `py-24 md:py-28`, which put roughly
 * 450px of air between content blocks at desktop.
 */

type Tone = 'ground' | 'surface' | 'raised';

const toneClass: Record<Tone, string> = {
  ground: 'bg-marketing-bg',
  surface: 'bg-marketing-surface',
  raised: 'bg-marketing-surface-elevated',
};

export type SectionProps = {
  children: ReactNode;
  id?: string;
  tone?: Tone;
  /** `wide` is for three-column grids; the default measure suits text and two columns. */
  width?: 'default' | 'wide';
  className?: string;
};

export function Section({ children, id, tone = 'ground', width = 'default', className }: SectionProps) {
  return (
    <section id={id} className={cn(toneClass[tone], 'py-16 sm:py-20 lg:py-24', className)}>
      <div className={cn('mx-auto px-5 sm:px-8', width === 'wide' ? 'max-w-6xl' : 'max-w-5xl')}>
        {children}
      </div>
    </section>
  );
}

export type SectionHeaderProps = {
  eyebrow?: string;
  title: string;
  /** The one-sentence standfirst under the heading. */
  lede?: string;
  className?: string;
};

/**
 * Headings were set in `text-page-title` — 1.5rem, an in-app token. Small type
 * inside large whitespace is what made the page feel simultaneously empty and
 * flat, so the marketing scale is its own thing.
 */
export function SectionHeader({ eyebrow, title, lede, className }: SectionHeaderProps) {
  return (
    <ScrollReveal className={cn('max-w-3xl', className)}>
      {eyebrow && <p className="m-0 text-label-caps text-marketing-accent">{eyebrow}</p>}
      <h2 className="m-0 mt-3 text-balance font-display text-3xl font-semibold leading-[1.12] tracking-tight text-marketing-foreground sm:text-[2.5rem]">
        {title}
      </h2>
      {lede && (
        <p className="m-0 mt-4 max-w-2xl text-pretty text-base leading-relaxed text-marketing-muted sm:text-lg">
          {lede}
        </p>
      )}
    </ScrollReveal>
  );
}

/**
 * The default card: a hairline, not a shadow.
 *
 * Elevation is now reserved for the only two places on the page that should
 * pull the eye — the hero chat and the worked example — so it means something
 * when it appears. Everything else sits flat against the ground.
 */
export const cardClass =
  'rounded-2xl border border-marketing-border bg-marketing-surface p-5 sm:p-6';
