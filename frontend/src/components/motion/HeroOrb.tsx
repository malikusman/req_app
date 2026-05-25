import { cn } from '../../lib/cn';

/** Lightweight hero glow — CSS-only fallback for shader blocks. */
export function HeroOrb({ className }: { className?: string }) {
  return (
    <div
      className={cn('pointer-events-none absolute inset-0 overflow-hidden', className)}
      aria-hidden
    >
      <div className="absolute left-1/2 top-1/3 h-[min(600px,80vw)] w-[min(600px,80vw)] -translate-x-1/2 -translate-y-1/2 rounded-full bg-[radial-gradient(circle,rgba(34,211,238,0.18)_0%,rgba(34,211,238,0.04)_40%,transparent_70%)] motion-reduce:opacity-50" />
      <div className="absolute right-[10%] top-[20%] h-48 w-48 rounded-full bg-[radial-gradient(circle,rgba(212,168,83,0.08)_0%,transparent_70%)]" />
    </div>
  );
}
