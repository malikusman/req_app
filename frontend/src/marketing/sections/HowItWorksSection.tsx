import { FileText, MessageCircle, ShieldCheck } from 'lucide-react';
import { motion, useReducedMotion } from 'motion/react';
import { ScrollReveal, Stagger } from '../../components/motion';
import { spring } from '../../lib/motion';
import { marketingContent } from '../content';

const icons = [FileText, MessageCircle, ShieldCheck] as const;

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
      className="relative rounded-2xl bg-marketing-surface p-7 shadow-marketing-card"
      whileHover={reduced ? undefined : { y: -4 }}
      transition={spring.soft}
    >
      <div className="flex items-center gap-3">
        <span className="flex h-9 w-9 items-center justify-center rounded-full bg-marketing-accent text-sm font-bold text-white">
          {index + 1}
        </span>
        <Icon className="h-5 w-5 text-marketing-accent" aria-hidden />
      </div>
      <h3 className="mt-5 font-display text-section-title text-marketing-foreground">{step.title}</h3>
      <p className="mt-2 text-sm leading-relaxed text-marketing-muted">{step.description}</p>
      <ul className="mt-5 space-y-2.5 border-t border-marketing-border pt-5">
        {step.details.map((detail) => (
          <li key={detail} className="flex gap-2.5 text-xs leading-relaxed text-marketing-muted">
            <span className="mt-1 h-1.5 w-1.5 shrink-0 rounded-full bg-marketing-accent" aria-hidden />
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
    <section id="how-it-works" className="border-b border-marketing-border bg-marketing-surface px-6 py-24 md:px-12 md:py-28">
      <div className="mx-auto max-w-6xl">
        <ScrollReveal>
          <p className="text-label-caps text-marketing-accent">{howItWorks.eyebrow}</p>
          <h2 className="mt-2 font-display text-page-title text-marketing-foreground">{howItWorks.title}</h2>
          <p className="mt-3 max-w-3xl text-lg text-marketing-muted">{howItWorks.subtitle}</p>
        </ScrollReveal>
        <Stagger className="mt-14 grid gap-6 lg:grid-cols-3" staggerDelay={0.1}>
          {howItWorks.steps.map((step, i) => (
            <StepCard key={step.title} step={step} index={i} />
          ))}
        </Stagger>
      </div>
    </section>
  );
}
