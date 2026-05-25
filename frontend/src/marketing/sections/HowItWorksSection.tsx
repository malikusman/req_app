import { MessageCircle, Brain, FileText } from 'lucide-react';
import { motion, useReducedMotion } from 'motion/react';
import { ScrollReveal, Stagger } from '../../components/motion';
import { spring } from '../../lib/motion';
import { marketingContent } from '../content';

const icons = [MessageCircle, Brain, FileText] as const;

function StepCard({
  step,
  index,
}: {
  step: (typeof marketingContent.howItWorks.steps)[number];
  index: number;
}) {
  const reduced = useReducedMotion();
  const Icon = icons[index] ?? MessageCircle;

  return (
    <motion.article
      className="rounded-card border border-border border-l-2 border-l-accent bg-surface p-6 shadow-card"
      whileHover={reduced ? undefined : { y: -4, boxShadow: '0 8px 24px rgb(0 0 0 / 0.08)' }}
      transition={spring.soft}
    >
      <span className="flex h-8 w-8 items-center justify-center rounded-full bg-accent-muted text-sm font-bold text-accent">
        {index + 1}
      </span>
      <Icon className="mt-4 h-6 w-6 text-accent" aria-hidden />
      <h3 className="mt-3 font-display text-section-title text-text-primary">{step.title}</h3>
      <p className="mt-2 text-sm leading-relaxed text-text-secondary">{step.description}</p>
      <ul className="mt-4 space-y-2 border-t border-border pt-4">
        {step.details.map((detail) => (
          <li key={detail} className="flex gap-2 text-xs text-text-secondary">
            <span className="text-accent" aria-hidden>
              —
            </span>
            {detail}
          </li>
        ))}
      </ul>
    </motion.article>
  );
}

export function HowItWorksSection() {
  const { howItWorks } = marketingContent;

  return (
    <section id="how-it-works" className="bg-surface-muted px-6 py-24 md:px-12 md:py-28">
      <div className="mx-auto max-w-6xl">
        <ScrollReveal>
          <h2 className="font-display text-page-title text-text-primary">{howItWorks.title}</h2>
          <p className="mt-3 max-w-3xl text-lg text-text-secondary">{howItWorks.subtitle}</p>
        </ScrollReveal>
        <Stagger className="mt-14 grid gap-8 lg:grid-cols-3" staggerDelay={0.1}>
          {howItWorks.steps.map((step, i) => (
            <StepCard key={step.title} step={step} index={i} />
          ))}
        </Stagger>
      </div>
    </section>
  );
}
