import { ClipboardList, Briefcase, Server, Bot, type LucideIcon } from 'lucide-react';
import { ScrollReveal, Stagger } from '../../components/motion';
import { marketingContent } from '../content';

const icons: LucideIcon[] = [ClipboardList, Briefcase, Server, Bot];

export function ProblemSection() {
  const { problem } = marketingContent;

  return (
    <section id="why-req" className="bg-marketing-bg px-6 py-24 md:px-12 md:py-28">
      <div className="mx-auto max-w-6xl">
        <ScrollReveal>
          <p className="text-label-caps text-marketing-accent">{problem.eyebrow}</p>
          <h2 className="mt-2 font-display text-page-title text-marketing-foreground">{problem.title}</h2>
          <p className="mt-3 max-w-3xl text-lg text-marketing-muted">{problem.subtitle}</p>
        </ScrollReveal>
        <Stagger className="mt-14 grid gap-5 md:grid-cols-2" staggerDelay={0.08}>
          {problem.pains.map((pain, i) => {
            const Icon = icons[i] ?? ClipboardList;
            return (
              <article
                key={pain.title}
                className="rounded-2xl bg-marketing-surface p-6 shadow-marketing-card transition-shadow hover:shadow-hero-mockup"
              >
                <div className="flex gap-4">
                  <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-marketing-accent-muted">
                    <Icon className="h-5 w-5 text-marketing-accent" aria-hidden />
                  </span>
                  <div>
                    <h3 className="font-display text-section-title text-marketing-foreground">{pain.title}</h3>
                    <p className="mt-2 text-sm leading-relaxed text-marketing-muted">{pain.description}</p>
                  </div>
                </div>
              </article>
            );
          })}
        </Stagger>
      </div>
    </section>
  );
}
