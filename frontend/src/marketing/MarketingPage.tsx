import { MarketingLayout } from '../components/layout/MarketingLayout';
import { MarketingNav } from './MarketingNav';
import { HeroSection } from './sections/HeroSection';
import { HowItWorksSection } from './sections/HowItWorksSection';
import { WhatYouDiscoverSection } from './sections/WhatYouDiscoverSection';
import { SocialProofSection } from './sections/SocialProofSection';
import { FinalCtaSection } from './sections/FinalCtaSection';
import { MarketingFooter } from './sections/MarketingFooter';

export function MarketingPage() {
  return (
    <MarketingLayout>
      <MarketingNav />
      <HeroSection />
      <HowItWorksSection />
      <WhatYouDiscoverSection />
      <SocialProofSection />
      <FinalCtaSection />
      <MarketingFooter />
    </MarketingLayout>
  );
}
