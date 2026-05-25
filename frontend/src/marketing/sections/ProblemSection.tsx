import { AlertCircle } from 'lucide-react';
import { ScrollReveal, Stagger } from '../../components/motion';
import { marketingContent } from '../content';

export function ProblemSection() {
  const { problem } = marketingContent;

  return (
    <section id="why-req" className="border-b border-border bg-surface px-6 py-24 md:px-12 md:py-28">
      <div className="mx-auto max-w-6xl">
        <ScrollReveal>
          <h2 className="font-display text-page-title text-text-primary">{problem.title}</h2>
          <p className="mt-3 max-w-3xl text-lg text-text-secondary">{problem.subtitle}</p>
        </ScrollReveal>
        <Stagger className="mt-14 grid gap-6 md:grid-cols-2" staggerDelay={0.08}>
          {problem.pains.map((pain) => (
            <article
              key={pain.title}
              className="rounded-card border border-border bg-surface-muted p-6 shadow-card"
            >
              <div className="flex gap-3">
                <AlertCircle className="mt-0.5 h-5 w-5 shrink-0 text-status-warning" aria-hidden />
                <div>
                  <h3 className="font-display text-section-title text-text-primary">{pain.title}</h3>
                  <p className="mt-2 text-sm leading-relaxed text-text-secondary">{pain.description}</p>
                </div>
              </div>
            </article>
          ))}
        </Stagger>
      </div>
    </section>
  );
}
