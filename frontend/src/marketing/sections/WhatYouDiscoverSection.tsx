import {
  AlertTriangle,
  Clock,
  GitBranch,
  Hand,
  Sparkles,
  Workflow,
  type LucideIcon,
} from 'lucide-react';
import { motion, useReducedMotion } from 'motion/react';
import { ScrollReveal } from '../../components/motion';
import { cn } from '../../lib/cn';
import { fadeUp, spring, staggerContainer, transition } from '../../lib/motion';
import { marketingContent, type DiscoverCardContent } from '../content';

const iconMap: Record<string, LucideIcon> = {
  Bottlenecks: AlertTriangle,
  'Manual workflows': Workflow,
  'Time sinks': Clock,
  'Cross-team dependencies': GitBranch,
  'AI opportunities': Sparkles,
  'Shadow processes': Hand,
};

function DiscoverCard({ card }: { card: DiscoverCardContent }) {
  const reduced = useReducedMotion();
  const Icon = iconMap[card.title] ?? AlertTriangle;

  return (
    <motion.div
      variants={fadeUp}
      transition={transition.reveal}
      className={cn(
        'rounded-card border border-marketing-border bg-marketing-surface/80 p-5 backdrop-blur-sm',
        card.span
      )}
      whileHover={reduced ? undefined : { scale: 1.02, borderColor: 'rgba(34, 211, 238, 0.35)' }}
      transition={reduced ? transition.reveal : spring.snappy}
    >
      <div className="flex h-9 w-9 items-center justify-center rounded-md bg-marketing-accent-muted">
        <Icon className="h-5 w-5 text-marketing-accent" aria-hidden />
      </div>
      <h3 className="mt-3 font-semibold text-marketing-foreground">{card.title}</h3>
      <p className="mt-2 text-sm leading-relaxed text-marketing-muted">{card.description}</p>
    </motion.div>
  );
}

export function WhatYouDiscoverSection() {
  const reduced = useReducedMotion();
  const { discover } = marketingContent;

  return (
    <section id="what-you-discover" className="border-y border-marketing-border bg-marketing-surface px-6 py-20 md:px-12 md:py-24">
      <div className="mx-auto max-w-6xl">
        <ScrollReveal>
          <p className="text-label-caps text-marketing-gold">Intelligence</p>
          <h2 className="mt-2 font-display text-page-title text-marketing-foreground">{discover.title}</h2>
          <p className="mt-3 max-w-3xl text-lg text-marketing-muted">{discover.subtitle}</p>
        </ScrollReveal>
        <motion.div
          className="mt-12 grid auto-rows-[minmax(160px,auto)] grid-cols-2 gap-4 lg:grid-cols-3"
          initial={reduced ? false : 'hidden'}
          whileInView={reduced ? undefined : 'visible'}
          viewport={{ once: true, margin: '-48px' }}
          variants={staggerContainer(0.06)}
        >
          {discover.cards.map((c) => (
            <DiscoverCard key={c.title} card={c} />
          ))}
        </motion.div>
      </div>
    </section>
  );
}
