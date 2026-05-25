import { Children, type ReactNode } from 'react';
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
  const items = Children.toArray(children);

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
