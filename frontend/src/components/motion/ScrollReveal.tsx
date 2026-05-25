import { type ReactNode } from 'react';
import { motion, useReducedMotion } from 'motion/react';
import { cn } from '../../lib/cn';
import { fadeIn, fadeUp, scaleIn, slideInRight, transition } from '../../lib/motion';

const variantMap = {
  fadeUp,
  fadeIn,
  scaleIn,
  slideInRight,
} as const;

type VariantName = keyof typeof variantMap;

export function ScrollReveal({
  children,
  className,
  variant = 'fadeUp',
  delay = 0,
  as = 'div',
}: {
  children: ReactNode;
  className?: string;
  variant?: VariantName;
  delay?: number;
  as?: 'div' | 'section' | 'article';
}) {
  const reduced = useReducedMotion();
  const Component = motion[as];

  if (reduced) {
    return <div className={className}>{children}</div>;
  }

  const variants = variantMap[variant];

  return (
    <Component
      className={cn(className)}
      initial="hidden"
      whileInView="visible"
      viewport={{ once: true, margin: '-60px' }}
      variants={variants}
      transition={{ ...transition.reveal, delay }}
    >
      {children}
    </Component>
  );
}
