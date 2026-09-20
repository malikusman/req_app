import { Stagger } from '../../components/motion';
import { cn } from '../../lib/cn';
import { Section, SectionHeader, cardClass } from '../components/Section';
import { marketingContent } from '../content';

/**
 * The icon tiles and the pulsing notification dot are gone. They were the same
 * accent-square-with-a-glyph used in five other sections, and a blinking dot on
 * a card that is not a notification is decoration pretending to be meaning.
 * The department badge is the only label these need.
 */
export function AlwaysOnSection() {
  const { alwaysOn } = marketingContent;

  return (
    <Section tone="ground" width="wide">
      <SectionHeader eyebrow={alwaysOn.eyebrow} title={alwaysOn.title} lede={alwaysOn.subtitle} />

      <Stagger className="mt-12 grid gap-4 md:grid-cols-3 lg:mt-14" staggerDelay={0.08}>
        {alwaysOn.items.map((item) => (
          <article key={item.title} className={cn(cardClass, 'flex h-full flex-col')}>
            <span className="self-start rounded-full bg-marketing-accent-muted px-2.5 py-1 text-[11px] font-semibold text-marketing-accent">
              {item.badge}
            </span>
            <h3 className="m-0 mt-4 font-display text-base font-semibold leading-snug text-marketing-foreground">
              {item.title}
            </h3>
            <p className="m-0 mt-2 text-pretty text-sm leading-relaxed text-marketing-muted">{item.body}</p>
          </article>
        ))}
      </Stagger>
    </Section>
  );
}
