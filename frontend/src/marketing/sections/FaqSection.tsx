import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from '@/components/shadcn/accordion';
import { Section, SectionHeader } from '../components/Section';
import { marketingContent } from '../content';

/**
 * Seven questions, not nine — and hairlines instead of nine stacked white
 * cards, which read as a list of boxes rather than a list of questions.
 *
 * Dropped: "Do we have to do all three stages?" (answered directly by the
 * closing line of How we work) and "Can we start from documents?" (a detail
 * that belongs in the first call, not on the homepage).
 */
export function FaqSection() {
  const { faq } = marketingContent;

  return (
    <Section id="faq" tone="surface">
      <SectionHeader eyebrow="FAQ" title={faq.title} />

      <Accordion type="single" collapsible defaultValue="item-0" className="mt-10 lg:mt-12">
        {faq.items.map((item, i) => (
          <AccordionItem key={item.q} value={`item-${i}`} className="border-b border-marketing-border">
            <AccordionTrigger className="py-5 text-left font-display text-base font-semibold text-marketing-foreground hover:no-underline">
              {item.q}
            </AccordionTrigger>
            <AccordionContent className="max-w-2xl text-pretty text-[0.9375rem] leading-relaxed text-marketing-muted">
              {item.a}
            </AccordionContent>
          </AccordionItem>
        ))}
      </Accordion>
    </Section>
  );
}
