import { useEffect, useRef, useState } from 'react';
import { animate, useInView, useReducedMotion } from 'motion/react';
import { cn } from '../../lib/cn';
import { duration, ease } from '../../lib/motion';

export function AnimatedNumber({
  value,
  className,
  suffix = '',
  decimals = 0,
}: {
  value: number;
  className?: string;
  suffix?: string;
  decimals?: number;
}) {
  const ref = useRef<HTMLSpanElement>(null);
  const inView = useInView(ref, { once: true, margin: '-40px' });
  const reduced = useReducedMotion();
  const [display, setDisplay] = useState(reduced ? value : 0);

  useEffect(() => {
    if (reduced) {
      setDisplay(value);
      return;
    }
    if (!inView) return;

    const controls = animate(0, value, {
      duration: duration.reveal,
      ease: ease.out,
      onUpdate: (v) => setDisplay(decimals > 0 ? v : Math.round(v)),
    });

    return () => controls.stop();
  }, [inView, value, reduced, decimals]);

  const formatted =
    decimals > 0 ? display.toFixed(decimals) : String(Math.round(display));

  return (
    <span ref={ref} className={cn('tabular-nums', className)}>
      {formatted}
      {suffix}
    </span>
  );
}
