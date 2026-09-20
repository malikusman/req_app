import { ScrollReveal } from '../../components/motion';
import { Section, SectionHeader } from '../components/Section';
import { marketingContent } from '../content';

/**
 * One concrete case does more than every claim on the site, so this is the
 * second and last elevated element on the page — a white card with a shadow on
 * a tinted ground, where everything else is a hairline.
 *
 * Mjadi has no clients, so this is explicitly an illustration rather than an
 * anonymised engagement; saying so is the point, not a caveat. The final block
 * is the one that earns trust: a recommendation *against* building something.
 */
export function WorkedExampleSection() {
  const { workedExample } = marketingContent;

  return (
    <Section id="example" tone="raised">
      <SectionHeader
        eyebrow={workedExample.eyebrow}
        title={workedExample.title}
        lede={workedExample.subtitle}
      />

      <ScrollReveal>
        <article className="mt-12 rounded-2xl bg-marketing-surface p-6 shadow-marketing-card sm:p-8 lg:mt-14">
          <p className="m-0 text-sm font-semibold text-marketing-foreground">{workedExample.company}</p>

          {/*
            Specificity is the strategy, and these three numbers are the whole
            of it. Lifted out of the prose so the eye lands on them first.
          */}
          <dl className="m-0 mt-6 grid gap-5 border-y border-marketing-border py-6 sm:grid-cols-3">
            {workedExample.figures.map((figure) => (
              <div key={figure.label}>
                <dt className="sr-only">{figure.label}</dt>
                <dd className="m-0 font-display text-3xl font-bold tabular-nums tracking-tight text-marketing-accent">
                  {figure.value}
                </dd>
                <p className="m-0 mt-1.5 text-xs leading-snug text-marketing-muted">{figure.label}</p>
              </div>
            ))}
          </dl>

          <dl className="m-0 mt-6 space-y-5">
            {workedExample.blocks.map((block) => (
              <div key={block.label}>
                <dt className="text-label-caps text-marketing-accent">{block.label}</dt>
                <dd className="m-0 mt-1.5 text-pretty text-[0.9375rem] leading-relaxed text-marketing-muted">
                  {block.body}
                </dd>
              </div>
            ))}
          </dl>

          {/* Set apart, because this is the part nobody expects. */}
          <div className="mt-6 border-t border-marketing-border pt-6">
            <p className="m-0 text-label-caps text-marketing-accent">{workedExample.counterpoint.label}</p>
            <p className="m-0 mt-1.5 text-pretty text-[0.9375rem] leading-relaxed text-marketing-muted">
              {workedExample.counterpoint.body}
            </p>
          </div>
        </article>
      </ScrollReveal>
    </Section>
  );
}
