import { useEffect, useState, type ReactNode } from 'react';
import { motion, useReducedMotion } from 'motion/react';
import { MoveRight } from 'lucide-react';
import { Button } from '@/components/shadcn/button';
import { cn } from '@/lib/utils';

export type MarketingAnimatedHeroProps = {
  eyebrow?: string;
  headlinePrefix: string;
  rotatingWords: string[];
  subhead: string;
  primaryCta: { label: string; onClick: () => void };
  secondaryCta?: { label: string; onClick: () => void };
  rightSlot?: ReactNode;
  className?: string;
};

export function MarketingAnimatedHero({
  eyebrow,
  headlinePrefix,
  rotatingWords,
  subhead,
  primaryCta,
  secondaryCta,
  rightSlot,
  className,
}: MarketingAnimatedHeroProps) {
  const reduced = useReducedMotion();
  const [wordIndex, setWordIndex] = useState(0);
  const staticWord = rotatingWords[0] ?? '';

  useEffect(() => {
    if (reduced || rotatingWords.length <= 1) return;
    const id = window.setInterval(() => {
      setWordIndex((i) => (i + 1) % rotatingWords.length);
    }, 2200);
    return () => window.clearInterval(id);
  }, [reduced, rotatingWords.length]);

  const activeIndex = reduced ? 0 : wordIndex;

  return (
    <div className={cn('relative w-full', className)}>
      <div className="mx-auto flex max-w-6xl flex-col items-center gap-12 px-6 py-16 lg:flex-row lg:items-center lg:py-24 lg:px-12">
        <div className="flex flex-1 flex-col items-center text-center lg:items-start lg:text-left">
          {eyebrow && (
            <p className="text-sm font-medium uppercase tracking-widest text-marketing-gold">
              {eyebrow}
            </p>
          )}
          <h1 className="mt-4 font-display text-4xl font-bold leading-tight tracking-tight text-marketing-foreground md:text-5xl lg:text-6xl">
            <span className="block">{headlinePrefix}</span>
            <span className="relative mt-2 flex h-[1.2em] w-full justify-center overflow-hidden lg:justify-start">
              {reduced ? (
                <span className="text-marketing-accent">{staticWord}</span>
              ) : (
                rotatingWords.map((word, index) => (
                  <motion.span
                    key={word}
                    className="absolute font-semibold text-marketing-accent"
                    initial={{ opacity: 0, y: '-100%' }}
                    animate={
                      activeIndex === index
                        ? { y: 0, opacity: 1 }
                        : {
                            y: activeIndex > index ? '-120%' : '120%',
                            opacity: 0,
                          }
                    }
                    transition={{ type: 'spring', stiffness: 50, damping: 18 }}
                  >
                    {word}
                  </motion.span>
                ))
              )}
            </span>
          </h1>
          <p className="mt-6 max-w-xl text-base leading-relaxed text-marketing-muted md:text-lg">
            {subhead}
          </p>
          <div className="mt-8 flex flex-wrap justify-center gap-3 lg:justify-start">
            <Button size="lg" variant="default" className="gap-2" onClick={primaryCta.onClick}>
              {primaryCta.label}
              <MoveRight className="h-4 w-4" />
            </Button>
            {secondaryCta && (
              <Button size="lg" variant="glass" className="gap-2" onClick={secondaryCta.onClick}>
                {secondaryCta.label}
              </Button>
            )}
          </div>
        </div>
        {rightSlot && <div className="relative w-full flex-1">{rightSlot}</div>}
      </div>
    </div>
  );
}
