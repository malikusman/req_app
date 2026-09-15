import { ScrollReveal, Stagger } from '../../components/motion';
import { marketingContent } from '../content';

/**
 * With a new firm, personal credibility carries the site — so the founders are
 * named, and the name itself is explained. Non-Arabic speakers cannot get the
 * story from the word alone, and it is a genuine asset.
 */
export function WhoWeAreSection() {
  const { whoWeAre } = marketingContent;

  return (
    <section id="who-we-are" className="bg-marketing-bg py-20 sm:py-28">
      <div className="mx-auto max-w-5xl px-5 sm:px-8">
        <ScrollReveal>
          <p className="m-0 text-label-caps text-marketing-accent">{whoWeAre.eyebrow}</p>
          <h2 className="m-0 mt-3 text-balance text-3xl font-semibold tracking-tight text-marketing-foreground sm:text-4xl">
            {whoWeAre.title}
          </h2>
          <p className="m-0 mt-4 max-w-2xl text-base text-marketing-muted">{whoWeAre.subtitle}</p>
        </ScrollReveal>

        <Stagger className="mt-10 grid gap-5 md:grid-cols-2">
          {whoWeAre.founders.map((founder) => (
            <article
              key={founder.name}
              className="rounded-2xl bg-marketing-surface p-6 shadow-marketing-card"
            >
              <h3 className="m-0 text-lg font-semibold text-marketing-foreground">{founder.name}</h3>
              <p className="m-0 mt-0.5 text-sm text-marketing-accent">{founder.role}</p>
              <p className="m-0 mt-3 text-base leading-relaxed text-marketing-muted">{founder.body}</p>
            </article>
          ))}
        </Stagger>

        <ScrollReveal>
          <div className="mt-6 rounded-2xl border border-marketing-border p-6">
            <p className="m-0 text-label-caps text-marketing-accent">{whoWeAre.name.label}</p>
            <p className="m-0 mt-1.5 text-base leading-relaxed text-marketing-muted">
              {whoWeAre.name.body}
            </p>
          </div>
        </ScrollReveal>
      </div>
    </section>
  );
}
