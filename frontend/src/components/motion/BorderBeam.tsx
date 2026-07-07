import { cn } from '../../lib/cn';

/** Animated gradient border — Magic UI–style accent on cards and mockups. */
export function BorderBeam({
  className,
  duration = 12,
  size = 200,
  colorFrom = '#0E9F6E',
  colorTo = '#5EEAD4',
}: {
  className?: string;
  duration?: number;
  size?: number;
  colorFrom?: string;
  colorTo?: string;
}) {
  return (
    <div
      className={cn(
        'pointer-events-none absolute inset-0 overflow-hidden rounded-[inherit]',
        className
      )}
      aria-hidden
    >
      <div
        className="absolute inset-0 animate-border-beam-spin rounded-[inherit] opacity-80 motion-reduce:hidden"
        style={{
          background: `conic-gradient(from 0deg at 50% 50%, transparent 0deg, ${colorFrom} 90deg, ${colorTo} 180deg, transparent 270deg)`,
          animationDuration: `${duration}s`,
          mask: 'linear-gradient(#fff 0 0) content-box, linear-gradient(#fff 0 0)',
          maskComposite: 'exclude',
          WebkitMaskComposite: 'xor',
          padding: '1px',
        }}
      />
      <div
        className="absolute animate-border-beam-pulse rounded-full blur-2xl motion-reduce:hidden"
        style={{
          width: size,
          height: size,
          left: '50%',
          top: '50%',
          marginLeft: -size / 2,
          marginTop: -size / 2,
          background: `radial-gradient(circle, ${colorFrom}40 0%, transparent 70%)`,
          animationDuration: `${duration * 0.75}s`,
        }}
      />
    </div>
  );
}
