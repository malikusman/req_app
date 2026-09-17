import { Ban, Clock, Coins, Wrench, type LucideIcon } from 'lucide-react';
import { Stagger } from '../../components/motion';
import { cn } from '../../lib/cn';
import { Section, SectionHeader, cardClass } from '../components/Section';
import { marketingContent, type DiscoverIcon } from '../content';

/**
 * Keyed on a stable `icon` field, not on the card title.
 *
 * The previous map was keyed by display copy ("Bottlenecks", "Manual
 * workflows"), so rewriting the titles silently dropped all six cards to the
 * same fallback icon — six identical warning triangles shipped to production.
 * Copy changes; keys do not.
 */
const icons: Record<DiscoverIcon, LucideIcon> = {
  clock: Clock,
  coins: Coins,
  wrench: Wrench,
  ban: Ban,
};

export function WhatYouDiscoverSection() {
  const { discover } = marketingContent;

  return (
    <Section id="what-you-get" tone="ground">
      <SectionHeader eyebrow={discover.eyebrow} title={discover.title} lede={discover.subtitle} />

      {/*
        Four equal cards. This was a six-card bento where the first spanned two
        columns and two rows while holding two lines of text, which left roughly
        half the section empty.
      */}
      <Stagger className="mt-12 grid gap-4 sm:grid-cols-2 lg:mt-14" staggerDelay={0.07}>
        {discover.cards.map((card) => {
          const Icon = icons[card.icon];
          return (
            <article key={card.title} className={cn(cardClass, 'h-full')}>
              <Icon className="h-5 w-5 text-marketing-accent" aria-hidden />
              <h3 className="m-0 mt-4 font-display text-base font-semibold text-marketing-foreground">
                {card.title}
              </h3>
              <p className="m-0 mt-2 text-pretty text-sm leading-relaxed text-marketing-muted">
                {card.description}
              </p>
            </article>
          );
        })}
      </Stagger>
    </Section>
  );
}
