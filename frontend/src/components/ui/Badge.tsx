import { type ReactNode } from 'react';
import { Badge as ShadcnBadge } from '@/components/shadcn/badge';
import { cn } from '../../lib/cn';

type Variant = 'success' | 'warning' | 'error' | 'info' | 'neutral';

const variantMap: Record<Variant, 'success' | 'warning' | 'error' | 'info' | 'neutral'> = {
  success: 'success',
  warning: 'warning',
  error: 'error',
  info: 'info',
  neutral: 'neutral',
};

export function Badge({
  variant = 'neutral',
  children,
  className,
}: {
  variant?: Variant;
  children: ReactNode;
  className?: string;
}) {
  return (
    <ShadcnBadge variant={variantMap[variant]} className={cn(className)}>
      {children}
    </ShadcnBadge>
  );
}

export function StatusBadge({
  status,
  className,
}: {
  status: 'active' | 'pending' | 'complete' | 'error' | 'inactive';
  className?: string;
}) {
  const config: Record<typeof status, { label: string; variant: Variant }> = {
    active: { label: 'Active', variant: 'success' },
    complete: { label: 'Complete', variant: 'success' },
    pending: { label: 'Pending', variant: 'warning' },
    error: { label: 'Error', variant: 'error' },
    inactive: { label: 'Inactive', variant: 'neutral' },
  };
  const { label, variant } = config[status];
  return (
    <Badge variant={variant} className={className}>
      {label}
    </Badge>
  );
}
