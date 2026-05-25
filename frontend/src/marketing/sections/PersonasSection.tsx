import { ScrollReveal, Stagger } from '../../components/motion';
import { marketingContent } from '../content';

export function PersonasSection() {
  const { personas } = marketingContent;

  return (
    <section className="border-b border-marketing-border bg-marketing-surface px-6 py-24 md:px-12 md:py-28">
      <div className="mx-auto max-w-6xl">
        <ScrollReveal>
          <p className="text-label-caps text-marketing-gold">Who it&apos;s for</p>
          <h2 className="mt-2 font-display text-page-title text-marketing-foreground">{personas.title}</h2>
          <p className="mt-3 max-w-3xl text-lg text-marketing-muted">{personas.subtitle}</p>
        </ScrollReveal>
        <Stagger className="mt-14 grid gap-6 sm:grid-cols-2" staggerDelay={0.08}>
          {personas.items.map((item) => (
            <article
              key={item.title}
              className="rounded-card border border-marketing-border bg-marketing-bg/40 p-6 backdrop-blur-sm"
            >
              <h3 className="font-display text-section-title text-marketing-foreground">{item.title}</h3>
              <p className="mt-2 text-sm leading-relaxed text-marketing-muted">{item.body}</p>
            </article>
          ))}
        </Stagger>
      </div>
    </section>
  );
}
