import { ScrollReveal, Stagger } from '../../components/motion';
import { marketingContent } from '../content';

export function PersonasSection() {
  const { personas } = marketingContent;

  return (
    <section className="border-y border-border bg-surface px-6 py-24 md:px-12 md:py-28">
      <div className="mx-auto max-w-6xl">
        <ScrollReveal>
          <h2 className="font-display text-page-title text-text-primary">{personas.title}</h2>
          <p className="mt-3 max-w-3xl text-lg text-text-secondary">{personas.subtitle}</p>
        </ScrollReveal>
        <Stagger className="mt-14 grid gap-6 sm:grid-cols-2" staggerDelay={0.08}>
          {personas.items.map((item) => (
            <article key={item.title} className="rounded-card border border-border p-6">
              <h3 className="font-display text-section-title text-text-primary">{item.title}</h3>
              <p className="mt-2 text-sm leading-relaxed text-text-secondary">{item.body}</p>
            </article>
          ))}
        </Stagger>
      </div>
    </section>
  );
}
