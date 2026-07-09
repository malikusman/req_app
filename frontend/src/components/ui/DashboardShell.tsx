import { type ReactNode } from 'react';
import { PageHeader } from './PageHeader';
import { Skeleton } from './Skeleton';
import { StatCardGrid } from '../motion';

export function DashboardShell({
  title,
  description,
  banner,
  kpiRow,
  loading,
  children,
}: {
  title: string;
  description: string;
  banner?: ReactNode;
  kpiRow?: ReactNode;
  loading?: boolean;
  children?: ReactNode;
}) {
  if (loading) {
    return (
      <div className="space-y-6">
        <Skeleton variant="text" />
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-6">
          {[1, 2, 3, 4, 5, 6].map((i) => (
            <Skeleton key={i} variant="card" />
          ))}
        </div>
        <Skeleton variant="card" />
      </div>
    );
  }

  return (
    <div className="space-y-8">
      <PageHeader title={title} description={description} />
      {banner}
      {kpiRow && <StatCardGrid className="grid-cols-2 lg:grid-cols-4">{kpiRow}</StatCardGrid>}
      {children}
    </div>
  );
}
