import { Children, Fragment, isValidElement, type ReactNode } from 'react';
import { motion, useReducedMotion } from 'motion/react';
import { cn } from '../../lib/cn';
import { fadeUp, stagger, staggerContainer, transition } from '../../lib/motion';

export function Stagger({
  children,
  className,
  staggerDelay = stagger.default,
  childClassName,
}: {
  children: ReactNode;
  className?: string;
  staggerDelay?: number;
  childClassName?: string;
}) {
  const reduced = useReducedMotion();
  // Flatten one level of <>…</> so a fragment of cards becomes one grid item per card,
  // matching how the fragment renders in the reduced-motion path.
  const items = Children.toArray(children).flatMap((child) =>
    isValidElement(child) && child.type === Fragment
      ? Children.toArray((child.props as { children?: ReactNode }).children)
      : [child]
  );

  if (reduced) {
    return <div className={className}>{children}</div>;
  }

  return (
    <motion.div
      className={cn(className)}
      initial="hidden"
      whileInView="visible"
      viewport={{ once: true, margin: '-48px' }}
      variants={staggerContainer(staggerDelay)}
    >
      {items.map((child, i) => (
        <motion.div
          key={i}
          className={childClassName}
          variants={fadeUp}
          transition={transition.reveal}
        >
          {child}
        </motion.div>
      ))}
    </motion.div>
  );
}
