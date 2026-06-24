import { type ReactNode } from 'react';
import { Card as ShadcnCard, CardContent, CardHeader, CardTitle } from '@/components/shadcn/card';
import { cn } from '../../lib/cn';

export function Card({
  title,
  children,
  className,
  padding = true,
}: {
  title?: string;
  children: ReactNode;
  className?: string;
  padding?: boolean;
}) {
  if (title) {
    return (
      <ShadcnCard className={cn(className)}>
        <CardHeader className={padding ? undefined : 'p-0 pb-0'}>
          <CardTitle className="text-section-title">{title}</CardTitle>
        </CardHeader>
        <CardContent className={padding ? undefined : 'p-0'}>{children}</CardContent>
      </ShadcnCard>
    );
  }

  return (
    <ShadcnCard className={cn(padding && 'p-6', className)}>
      {children}
    </ShadcnCard>
  );
}
