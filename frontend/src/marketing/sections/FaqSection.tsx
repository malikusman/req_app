import { ScrollReveal } from '../../components/motion';
import { marketingContent } from '../content';
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from '@/components/shadcn/accordion';

export function FaqSection() {
  const { faq } = marketingContent;

  return (
    <section id="faq" className="bg-marketing-bg px-6 py-24 md:px-12 md:py-28">
      <div className="mx-auto max-w-3xl">
        <ScrollReveal>
          <p className="text-center text-label-caps text-marketing-accent">FAQ</p>
          <h2 className="mt-2 text-center font-display text-page-title text-marketing-foreground">{faq.title}</h2>
        </ScrollReveal>
        <Accordion type="single" collapsible defaultValue="item-0" className="mt-10 space-y-3">
          {faq.items.map((item, i) => (
            <AccordionItem
              key={item.q}
              value={`item-${i}`}
              className="overflow-hidden rounded-2xl border-none bg-marketing-surface px-6 shadow-marketing-card"
            >
              <AccordionTrigger className="py-5 text-left font-semibold text-marketing-foreground hover:no-underline">
                {item.q}
              </AccordionTrigger>
              <AccordionContent className="text-sm leading-relaxed text-marketing-muted">
                {item.a}
              </AccordionContent>
            </AccordionItem>
          ))}
        </Accordion>
      </div>
    </section>
  );
}
