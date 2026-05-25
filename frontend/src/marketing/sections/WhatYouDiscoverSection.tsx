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
        'rounded-card border border-white/[0.08] bg-white/[0.04] p-5 backdrop-blur-sm',
        card.span
      )}
      whileHover={reduced ? undefined : { scale: 1.02, backgroundColor: 'rgba(255,255,255,0.07)' }}
      transition={reduced ? transition.reveal : spring.snappy}
    >
      <div className="flex h-9 w-9 items-center justify-center rounded-md bg-accent/10">
        <Icon className="h-5 w-5 text-accent" aria-hidden />
      </div>
      <h3 className="mt-3 font-semibold">{card.title}</h3>
      <p className="mt-2 text-sm leading-relaxed text-gray-400">{card.description}</p>
    </motion.div>
  );
}

export function WhatYouDiscoverSection() {
  const reduced = useReducedMotion();
  const { discover } = marketingContent;

  return (
    <section id="what-you-discover" className="bg-sidebar px-6 py-20 text-text-inverse md:px-12 md:py-24">
      <div className="mx-auto max-w-6xl">
        <ScrollReveal>
          <h2 className="font-display text-page-title">{discover.title}</h2>
          <p className="mt-3 max-w-3xl text-lg text-gray-400">{discover.subtitle}</p>
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
