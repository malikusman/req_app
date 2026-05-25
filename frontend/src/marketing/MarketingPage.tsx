import { MarketingLayout } from '../components/layout/MarketingLayout';
import { MarketingNav } from './MarketingNav';
import { HeroSection } from './sections/HeroSection';
import { ProblemSection } from './sections/ProblemSection';
import { HowItWorksSection } from './sections/HowItWorksSection';
import { WhatYouDiscoverSection } from './sections/WhatYouDiscoverSection';
import { PlatformSection } from './sections/PlatformSection';
import { PersonasSection } from './sections/PersonasSection';
import { SocialProofSection } from './sections/SocialProofSection';
import { FaqSection } from './sections/FaqSection';
import { FinalCtaSection } from './sections/FinalCtaSection';
import { MarketingFooter } from './sections/MarketingFooter';

export function MarketingPage() {
  return (
    <MarketingLayout>
      <MarketingNav />
      <HeroSection />
      <ProblemSection />
      <HowItWorksSection />
      <WhatYouDiscoverSection />
      <PlatformSection />
      <PersonasSection />
      <SocialProofSection />
      <FaqSection />
      <FinalCtaSection />
      <MarketingFooter />
    </MarketingLayout>
  );
}
