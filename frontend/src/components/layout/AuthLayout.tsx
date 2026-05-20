import type { ReactNode } from 'react';
import { Check } from 'lucide-react';
import { cn } from '../../lib/cn';

export type AuthPortal = 'platform' | 'company' | 'reviewer';

const portalFeatures: Record<AuthPortal, string[]> = {
  platform: [
    'Manage all companies and trials',
    'Review and approve reports',
    'Monitor system health',
  ],
  company: [
    'Track discovery progress',
    'View AI-generated insights',
    'Generate transformation reports',
  ],
  reviewer: [
    'Annotate and review reports',
    'Request employee follow-ups',
    'Collaborate with co-reviewers',
  ],
};

type AuthLayoutProps = {
  portal: AuthPortal;
  portalName: string;
  tagline: string;
  children: ReactNode;
};

export function AuthLayout({ portal, portalName, tagline, children }: AuthLayoutProps) {
  const features = portalFeatures[portal];

  return (
    <div className="flex min-h-screen flex-col md:flex-row">
      <div
        className={cn(
          'relative flex w-full flex-col justify-between overflow-hidden md:w-[40%]',
          'bg-sidebar px-8 py-10 text-text-inverse md:px-10 md:py-12'
        )}
      >
        <div
          className="pointer-events-none absolute inset-0 opacity-[0.09] animate-grid-drift bg-[length:64px_64px] bg-[linear-gradient(rgba(255,255,255,0.07)_1px,transparent_1px),linear-gradient(90deg,rgba(255,255,255,0.07)_1px,transparent_1px)]"
          aria-hidden
        />
        <div
          className="pointer-events-none absolute right-0 top-0 h-full w-px bg-gradient-to-b from-transparent via-accent to-transparent opacity-60"
          aria-hidden
        />

        <div className="relative z-10">
          <div className="flex items-center gap-2">
            <span className="h-6 w-2 shrink-0 rounded-sm bg-accent" aria-hidden />
            <span className="font-display text-3xl font-bold tracking-tight text-white">Req</span>
          </div>
          <p className="mt-8 max-w-sm text-lg font-medium text-text-inverse">{portalName}</p>
          <p className="mt-2 max-w-sm text-sm text-text-inverse/70">{tagline}</p>
          <ul className="mt-8 space-y-3">
            {features.map((item) => (
              <li key={item} className="flex items-start gap-2 text-sm text-text-inverse/80">
                <Check className="mt-0.5 h-4 w-4 shrink-0 text-accent" aria-hidden />
                <span>{item}</span>
              </li>
            ))}
          </ul>
        </div>

        <blockquote className="relative z-10 mt-10 text-sm italic text-white/50 md:mt-0">
          &ldquo;The most actionable operational intelligence we&apos;ve ever seen.&rdquo;
        </blockquote>
      </div>

      <div className="flex min-h-screen w-full flex-col items-center justify-center bg-surface px-6 py-10 md:w-[60%] md:px-8 md:py-12">
        <div className="w-full max-w-md">{children}</div>
      </div>
    </div>
  );
}
