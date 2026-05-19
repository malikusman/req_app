import type { ReactNode } from 'react';
import { cn } from '../../lib/cn';

type AuthLayoutProps = {
  portalName: string;
  tagline: string;
  children: ReactNode;
};

export function AuthLayout({ portalName, tagline, children }: AuthLayoutProps) {
  return (
    <div className="flex min-h-screen">
      <div
        className={cn(
          'relative flex w-[40%] flex-col justify-between overflow-hidden',
          'bg-sidebar px-10 py-12 text-text-inverse'
        )}
      >
        <div
          className="pointer-events-none absolute inset-0 opacity-[0.07]"
          style={{
            backgroundImage:
              'linear-gradient(#fff 1px, transparent 1px), linear-gradient(90deg, #fff 1px, transparent 1px)',
            backgroundSize: '64px 64px',
            animation: 'gridDrift 60s linear infinite',
          }}
          aria-hidden
        />
        <div className="relative z-10">
          <span className="font-display text-2xl font-semibold tracking-tight">Req</span>
          <p className="mt-6 max-w-sm text-lg font-medium text-text-inverse">{portalName}</p>
          <p className="mt-2 max-w-sm text-sm text-text-inverse/70">{tagline}</p>
        </div>
        <span className="relative z-10 text-xs text-text-inverse/40">
          &copy; {new Date().getFullYear()} Req
        </span>
      </div>
      <div className="flex w-[60%] flex-col items-center justify-center bg-surface px-8 py-12">
        <div className="w-full max-w-md">{children}</div>
      </div>
    </div>
  );
}
