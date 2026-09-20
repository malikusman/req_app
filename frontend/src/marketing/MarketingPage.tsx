import { MarketingLayout } from '../components/layout/MarketingLayout';
import { MarketingNav } from './MarketingNav';
import { HeroSection } from './sections/HeroSection';
import { ProblemSection } from './sections/ProblemSection';
import { WhatYouDiscoverSection } from './sections/WhatYouDiscoverSection';
import { WorkedExampleSection } from './sections/WorkedExampleSection';
import { AlwaysOnSection } from './sections/AlwaysOnSection';
import { HowItWorksSection } from './sections/HowItWorksSection';
import { WhoWeAreSection } from './sections/WhoWeAreSection';
import { FaqSection } from './sections/FaqSection';
import { FinalCtaSection } from './sections/FinalCtaSection';
import { MarketingFooter } from './sections/MarketingFooter';

/**
 * Nine blocks, and the order is the argument.
 *
 * Their problem comes before our process: a visitor does not care how we work
 * until they believe we can help. So the situation they recognise, then what
 * they would get, then proof it is real — and only then the three stages.
 *
 * Four sections were removed rather than shortened:
 *   - The platform      12 bullets describing our machinery in our words. Its
 *                       three load-bearing facts moved into How we work.
 *   - Who it is for     Four persona cards restating the situation section.
 *   - Industries strip  One line of context; it belongs to the hero.
 *   - What we won't do  A statement of character, so it belongs with Who we are.
 *
 * Tones alternate deliberately (ground / surface / raised) so the page has a
 * rhythm. Every section used to sit on the same ground with the same white
 * cards, which is why it read as one undifferentiated list.
 */
export function MarketingPage() {
  return (
    <MarketingLayout>
      <MarketingNav />
      <HeroSection />
      <ProblemSection />
      <WhatYouDiscoverSection />
      <WorkedExampleSection />
      <AlwaysOnSection />
      <HowItWorksSection />
      <WhoWeAreSection />
      <FaqSection />
      <FinalCtaSection />
      <MarketingFooter />
    </MarketingLayout>
  );
}
