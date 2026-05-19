import type { ReactNode } from 'react';

type MarketingLayoutProps = {
  children: ReactNode;
};

export function MarketingLayout({ children }: MarketingLayoutProps) {
  return <div className="min-h-screen bg-surface">{children}</div>;
}
