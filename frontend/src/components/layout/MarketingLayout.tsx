import type { ReactNode } from 'react';

type MarketingLayoutProps = {
  children: ReactNode;
};

export function MarketingLayout({ children }: MarketingLayoutProps) {
  return (
    <div className="marketing min-h-screen bg-marketing-bg text-marketing-foreground">
      {children}
    </div>
  );
}
