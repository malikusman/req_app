import { ScrollReveal, Stagger } from '../../components/motion';
import { Section, SectionHeader } from '../components/Section';
import { marketingContent } from '../content';

/**
 * Four textures rather than five, and no cards.
 *
 * These were white boxes with decorative icons — a clipboard, a briefcase, a
 * server — that carried no information and made the section look like every
 * other one. A rule above each item is enough structure, and it lets the
 * writing do the work, which is the only thing this section has.
 */
export function ProblemSection() {
  const { problem } = marketingContent;

  return (
    <Section id="situation" tone="surface">
      <SectionHeader eyebrow={problem.eyebrow} title={problem.title} lede={problem.subtitle} />

      <Stagger className="mt-12 grid gap-x-10 gap-y-8 sm:grid-cols-2 lg:mt-14" staggerDelay={0.08}>
        {problem.pains.map((pain) => (
          <article key={pain.title} className="border-t border-marketing-border pt-6">
            <h3 className="m-0 font-display text-lg font-semibold leading-snug text-marketing-foreground">
              {pain.title}
            </h3>
            <p className="m-0 mt-2.5 text-pretty text-[0.9375rem] leading-relaxed text-marketing-muted">
              {pain.description}
            </p>
          </article>
        ))}
      </Stagger>

      {/*
        The line the section exists to earn. It was written into the content and
        never rendered by anything, so the section has been stopping one beat
        short of its own argument.
      */}
      <ScrollReveal>
        <p className="m-0 mt-12 max-w-3xl border-l-2 border-marketing-accent pl-5 text-pretty font-display text-lg font-medium leading-relaxed text-marketing-foreground sm:mt-14 sm:text-xl">
          {problem.closing}
        </p>
      </ScrollReveal>
    </Section>
  );
}
