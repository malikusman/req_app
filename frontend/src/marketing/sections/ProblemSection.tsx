import { AlertCircle } from 'lucide-react';
import { ScrollReveal, Stagger } from '../../components/motion';
import { marketingContent } from '../content';

export function ProblemSection() {
  const { problem } = marketingContent;

  return (
    <section id="why-req" className="border-b border-marketing-border bg-marketing-surface px-6 py-24 md:px-12 md:py-28">
      <div className="mx-auto max-w-6xl">
        <ScrollReveal>
          <h2 className="font-display text-page-title text-marketing-foreground">{problem.title}</h2>
          <p className="mt-3 max-w-3xl text-lg text-marketing-muted">{problem.subtitle}</p>
        </ScrollReveal>
        <Stagger className="mt-14 grid gap-6 md:grid-cols-2" staggerDelay={0.08}>
          {problem.pains.map((pain) => (
            <article
              key={pain.title}
              className="rounded-card border border-marketing-border bg-marketing-bg/60 p-6 shadow-marketing-card backdrop-blur-sm transition-colors hover:border-marketing-accent/30"
            >
              <div className="flex gap-3">
                <AlertCircle className="mt-0.5 h-5 w-5 shrink-0 text-marketing-gold" aria-hidden />
                <div>
                  <h3 className="font-display text-section-title text-marketing-foreground">
                    {pain.title}
                  </h3>
                  <p className="mt-2 text-sm leading-relaxed text-marketing-muted">{pain.description}</p>
                </div>
              </div>
            </article>
          ))}
        </Stagger>
      </div>
    </section>
  );
}
