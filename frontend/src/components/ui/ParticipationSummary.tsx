import { CheckCircle2, Percent, PlayCircle, Users } from 'lucide-react';
import { StatCardGrid } from '../motion';
import { DepartmentHeatmap, type HeatmapCell } from './DepartmentHeatmap';
import { FunnelChart } from './FunnelChart';
import { StatCard } from './StatCard';

export type ParticipationStats = {
  invited: number;
  started: number;
  completed: number;
  completion_rate: number;
};

export function ParticipationSummary({
  participation,
  departmentCoverage = [],
}: {
  participation: ParticipationStats;
  departmentCoverage?: HeatmapCell[];
}) {
  const { invited, started, completed, completion_rate: rate } = participation;
  const completionPct = Math.round(rate * 100);

  return (
    <div className="space-y-6">
      <StatCardGrid className="grid-cols-2 lg:grid-cols-4">
        <StatCard label="Invited" value={invited} icon={<Users className="h-5 w-5 text-accent" />} />
        <StatCard label="Started" value={started} icon={<PlayCircle className="h-5 w-5 text-accent" />} />
        <StatCard
          label="Completed"
          value={completed}
          icon={<CheckCircle2 className="h-5 w-5 text-accent" />}
        />
        <StatCard
          label="Completion rate"
          value={`${completionPct}%`}
          icon={<Percent className="h-5 w-5 text-accent" />}
        />
      </StatCardGrid>

      {invited > 0 ? (
        <div>
          <div className="mb-3 flex items-center justify-between">
            <p className="text-label-caps text-text-secondary">Interview funnel</p>
            <span className="text-sm font-medium text-text-primary">
              {completed} of {invited} finished
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
        <p className="text-sm text-text-secondary">No employees invited yet.</p>
      )}

      {departmentCoverage.length > 0 && (
        <div>
          <p className="mb-3 text-label-caps text-text-secondary">Department coverage</p>
          <DepartmentHeatmap cells={departmentCoverage} />
        </div>
      )}
    </div>
  );
}
