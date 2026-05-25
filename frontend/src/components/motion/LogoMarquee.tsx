import { cn } from '../../lib/cn';

export function LogoMarquee({
  items,
  className,
}: {
  items: string[];
  className?: string;
}) {
  const doubled = [...items, ...items];

  return (
    <div
      className={cn('relative overflow-hidden', className)}
      aria-label="Trusted companies"
    >
      <div className="pointer-events-none absolute inset-y-0 left-0 z-10 w-16 bg-gradient-to-r from-marketing-bg to-transparent" />
      <div className="pointer-events-none absolute inset-y-0 right-0 z-10 w-16 bg-gradient-to-l from-marketing-bg to-transparent" />
      <div className="flex w-max animate-marquee gap-12 motion-reduce:animate-none">
        {doubled.map((name, i) => (
          <span
            key={`${name}-${i}`}
            className="shrink-0 text-lg font-semibold text-text-secondary"
          >
            {name}
          </span>
        ))}
      </div>
    </div>
  );
}
