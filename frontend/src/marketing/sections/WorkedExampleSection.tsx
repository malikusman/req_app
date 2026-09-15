import { ScrollReveal } from '../../components/motion';
import { marketingContent } from '../content';

/**
 * One concrete case does more than every claim on the site.
 *
 * Mjadi has no clients, so this is explicitly an illustration rather than an
 * anonymised engagement — saying so is the point, not a caveat. The final block
 * is the one that earns trust: a recommendation *against* building something.
 */
export function WorkedExampleSection() {
  const { workedExample } = marketingContent;

  return (
    <section id="example" className="bg-marketing-surface-elevated py-20 sm:py-28">
      <div className="mx-auto max-w-4xl px-5 sm:px-8">
        <ScrollReveal>
          <p className="m-0 text-label-caps text-marketing-accent">{workedExample.eyebrow}</p>
          <h2 className="m-0 mt-3 text-balance text-3xl font-semibold tracking-tight text-marketing-foreground sm:text-4xl">
            {workedExample.title}
          </h2>
          <p className="m-0 mt-4 max-w-2xl text-base text-marketing-muted">{workedExample.subtitle}</p>
        </ScrollReveal>

        <ScrollReveal>
          <article className="mt-10 rounded-2xl bg-marketing-surface p-6 shadow-marketing-card sm:p-8">
            <p className="m-0 text-sm font-semibold text-marketing-foreground">{workedExample.company}</p>

            <dl className="m-0 mt-6 space-y-5">
              {workedExample.blocks.map((block) => (
                <div key={block.label}>
                  <dt className="text-label-caps text-marketing-accent">{block.label}</dt>
                  <dd className="m-0 mt-1.5 text-base leading-relaxed text-marketing-muted">{block.body}</dd>
                </div>
              ))}
            </dl>

            {/* Set apart, because this is the part nobody expects. */}
            <div className="mt-7 border-t border-marketing-border pt-6">
              <p className="m-0 text-label-caps text-marketing-accent">
                {workedExample.counterpoint.label}
              </p>
              <p className="m-0 mt-1.5 text-base leading-relaxed text-marketing-muted">
                {workedExample.counterpoint.body}
              </p>
            </div>
          </article>
        </ScrollReveal>
      </div>
    </section>
  );
}
