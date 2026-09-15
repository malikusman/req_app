import { MarketingLayout } from '../components/layout/MarketingLayout';
import { MarketingNav } from './MarketingNav';
import { HeroSection } from './sections/HeroSection';
import { LogoStripSection } from './sections/LogoStripSection';
import { ProblemSection } from './sections/ProblemSection';
import { WhatYouDiscoverSection } from './sections/WhatYouDiscoverSection';
import { WorkedExampleSection } from './sections/WorkedExampleSection';
import { AlwaysOnSection } from './sections/AlwaysOnSection';
import { HowItWorksSection } from './sections/HowItWorksSection';
import { PlatformSection } from './sections/PlatformSection';
import { PersonasSection } from './sections/PersonasSection';
import { WhoWeAreSection } from './sections/WhoWeAreSection';
import { WhatWeWontDoSection } from './sections/WhatWeWontDoSection';
import { FaqSection } from './sections/FaqSection';
import { FinalCtaSection } from './sections/FinalCtaSection';
import { MarketingFooter } from './sections/MarketingFooter';

/**
 * Order follows the website brief, and the order is the argument.
 *
 * Their problem comes before our process: a visitor does not care how we work
 * until they believe we can help. So the situation they recognise, then what
 * they would get, then proof it is real — and only then the three stages.
 * Methodology used to sit third; it now sits sixth, deliberately.
 *
 * The method pull-quote was dropped: a quote with nobody's name on it is a
 * credibility device for a firm with clients, and Mjadi has none yet.
 */
export function MarketingPage() {
  return (
    <MarketingLayout>
      <MarketingNav />
      <HeroSection />
      <LogoStripSection />
      <ProblemSection />
      <WhatYouDiscoverSection />
      <WorkedExampleSection />
      <AlwaysOnSection />
      <HowItWorksSection />
      <PlatformSection />
      <PersonasSection />
      <WhoWeAreSection />
      <WhatWeWontDoSection />
      <FaqSection />
      <FinalCtaSection />
      <MarketingFooter />
    </MarketingLayout>
  );
}
