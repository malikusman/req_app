import { MarketingLayout } from '../components/layout/MarketingLayout';
import { MarketingNav } from './MarketingNav';
import { HeroSection } from './sections/HeroSection';
import { LogoStripSection } from './sections/LogoStripSection';
import { ProblemSection } from './sections/ProblemSection';
import { HowItWorksSection } from './sections/HowItWorksSection';
import { EvidenceFlowSection } from './sections/EvidenceFlowSection';
import { WhatYouDiscoverSection } from './sections/WhatYouDiscoverSection';
import { AlwaysOnSection } from './sections/AlwaysOnSection';
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
      <LogoStripSection />
      <ProblemSection />
      <HowItWorksSection />
      <EvidenceFlowSection />
      <WhatYouDiscoverSection />
      <AlwaysOnSection />
      <PlatformSection />
      <PersonasSection />
      <SocialProofSection />
      <FaqSection />
      <FinalCtaSection />
      <MarketingFooter />
    </MarketingLayout>
  );
}
