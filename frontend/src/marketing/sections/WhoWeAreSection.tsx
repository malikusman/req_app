import { ScrollReveal, Stagger } from '../../components/motion';
import { Section, SectionHeader } from '../components/Section';
import { marketingContent } from '../content';

/**
 * Who we are and what we refuse to do, in one section.
 *
 * "What we will not do" was a separate band of four cards, each with the same
 * X icon. It is a statement of character, which is the subject of this section
 * already — so it lives here as a list, and the page loses a boundary.
 *
 * The name is explained because a non-Arabic speaker cannot get the story from
 * the word alone, and it is a genuine asset.
 */
export function WhoWeAreSection() {
  const { whoWeAre } = marketingContent;

  return (
    <Section id="who-we-are" tone="ground">
      <SectionHeader eyebrow={whoWeAre.eyebrow} title={whoWeAre.title} lede={whoWeAre.subtitle} />

      <Stagger className="mt-12 grid gap-x-10 gap-y-8 sm:grid-cols-2 lg:mt-14" staggerDelay={0.08}>
        {whoWeAre.founders.map((founder) => (
          <article key={founder.name} className="border-t border-marketing-border pt-6">
            <h3 className="m-0 font-display text-lg font-semibold text-marketing-foreground">
              {founder.name}
            </h3>
            <p className="m-0 mt-0.5 text-sm text-marketing-accent">{founder.role}</p>
            <p className="m-0 mt-3 text-pretty text-[0.9375rem] leading-relaxed text-marketing-muted">
              {founder.body}
            </p>
          </article>
        ))}
      </Stagger>

      <ScrollReveal>
        <div className="mt-10 rounded-2xl bg-marketing-surface-elevated p-6">
          <p className="m-0 text-label-caps text-marketing-accent">{whoWeAre.name.label}</p>
          <p className="m-0 mt-1.5 max-w-3xl text-pretty text-[0.9375rem] leading-relaxed text-marketing-muted">
            {whoWeAre.name.body}
          </p>
        </div>
      </ScrollReveal>

      <ScrollReveal>
        <div className="mt-12">
          <h3 className="m-0 font-display text-xl font-semibold text-marketing-foreground">
            {whoWeAre.stance.label}
          </h3>
          <ul className="m-0 mt-5 grid list-none gap-x-10 gap-y-4 p-0 sm:grid-cols-2">
            {whoWeAre.stance.items.map((item) => (
              <li
                key={item}
                className="border-t border-marketing-border pt-4 text-pretty text-[0.9375rem] leading-relaxed text-marketing-muted"
              >
                {item}
              </li>
            ))}
          </ul>
        </div>
      </ScrollReveal>
    </Section>
  );
}
