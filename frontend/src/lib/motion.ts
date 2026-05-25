import type { Transition, Variants } from 'motion/react';

/** Shared motion tokens — import durations/easing here, not inline magic numbers. */

export const duration = {
  instant: 0.1,
  fast: 0.15,
  normal: 0.25,
  slow: 0.4,
  reveal: 0.55,
} as const;

export const ease = {
  out: [0.22, 1, 0.36, 1] as const,
  inOut: [0.45, 0, 0.55, 1] as const,
};

export const spring = {
  snappy: { type: 'spring', stiffness: 500, damping: 32 } as Transition,
  soft: { type: 'spring', stiffness: 260, damping: 24 } as Transition,
  gentle: { type: 'spring', stiffness: 180, damping: 22 } as Transition,
};

export const transition = {
  fast: { duration: duration.fast, ease: ease.out },
  normal: { duration: duration.normal, ease: ease.out },
  reveal: { duration: duration.reveal, ease: ease.out },
} as const;

export const stagger = {
  tight: 0.05,
  default: 0.08,
  relaxed: 0.1,
} as const;

export const fadeUp: Variants = {
  hidden: { opacity: 0, y: 20 },
  visible: { opacity: 1, y: 0 },
};

export const fadeIn: Variants = {
  hidden: { opacity: 0 },
  visible: { opacity: 1 },
};

export const scaleIn: Variants = {
  hidden: { opacity: 0, scale: 0.96 },
  visible: { opacity: 1, scale: 1 },
};

export const slideInRight: Variants = {
  hidden: { opacity: 0, x: 24 },
  visible: { opacity: 1, x: 0 },
};

export const messageBubble: Variants = {
  hidden: { opacity: 0, y: 10, scale: 0.98 },
  visible: { opacity: 1, y: 0, scale: 1 },
  exit: { opacity: 0, y: -6, scale: 0.98 },
};

export const staggerContainer = (staggerChildren = stagger.default): Variants => ({
  hidden: {},
  visible: {
    transition: { staggerChildren, delayChildren: 0.05 },
  },
});

export const pageTransition = {
  initial: { opacity: 0, y: 10 },
  animate: { opacity: 1, y: 0 },
  exit: { opacity: 0, y: -6 },
};

export const tapScale = { hover: 1.02, tap: 0.98 } as const;

export const shake: Variants = {
  idle: { x: 0 },
  shake: {
    x: [0, -6, 6, -4, 4, 0],
    transition: { duration: 0.4 },
  },
};
