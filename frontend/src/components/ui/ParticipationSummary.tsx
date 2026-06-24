import { CheckCircle2, Percent, PlayCircle, Users } from 'lucide-react';
import { StatCardGrid } from '../motion';
import { DepartmentHeatmap, type HeatmapCell } from './DepartmentHeatmap';
import { FunnelChart } from './FunnelChart';
import { StatCard } from './StatCard';
import { cn } from '../../lib/cn';

export type ParticipationStats = {
  invited: number;
  started: number;
  completed: number;
  completion_rate: number;
};

export function ParticipationSummary({
  participation,
  departmentCoverage = [],
  compact = false,
}: {
  participation: ParticipationStats;
  departmentCoverage?: HeatmapCell[];
  compact?: boolean;
}) {
  const { invited, started, completed, completion_rate: rate } = participation;
  const completionPct = Math.round(rate * 100);

  return (
    <div className={cn('min-w-0', compact ? 'space-y-4' : 'space-y-6')}>
      {!compact && (
        <StatCardGrid className="grid-cols-2 lg:grid-cols-4">
          <StatCard label="Invited" value={invited} icon={<Users className="h-5 w-5 text-primary" />} />
          <StatCard label="Started" value={started} icon={<PlayCircle className="h-5 w-5 text-primary" />} />
          <StatCard
            label="Completed"
            value={completed}
            icon={<CheckCircle2 className="h-5 w-5 text-primary" />}
          />
          <StatCard
            label="Completion rate"
            value={`${completionPct}%`}
            icon={<Percent className="h-5 w-5 text-primary" />}
          />
        </StatCardGrid>
      )}

      {invited > 0 ? (
        <div className="min-w-0 overflow-hidden">
          <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
            <p className="text-label-caps text-muted-foreground">Interview funnel</p>
            <span className="text-sm font-medium text-foreground">
              {completed} of {invited} finished ({completionPct}%)
            </span>
          </div>
          <FunnelChart
            stages={[
              { label: 'Invited', count: invited },
              { label: 'Started', count: started },
              { label: 'Completed', count: completed },
            ]}
          />
        </div>
      ) : (
        <p className="text-sm text-muted-foreground">No employees invited yet.</p>
      )}

      {departmentCoverage.length > 0 && (
        <div className="min-w-0 overflow-hidden">
          <p className="mb-3 text-label-caps text-muted-foreground">Department coverage</p>
          <DepartmentHeatmap cells={departmentCoverage} />
        </div>
      )}
    </div>
  );
}
