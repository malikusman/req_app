import { motion } from 'motion/react';
import { RadialBarChart, RadialBar, ResponsiveContainer, PolarAngleAxis } from 'recharts';
import { cn } from '../../lib/cn';

const BREAKDOWN_LABELS: Record<string, string> = {
  employees_interviewed: 'Employees interviewed',
  departments_represented: 'Departments covered',
  confirmed_patterns: 'Confirmed patterns',
  multimodal_contributions: 'Multimodal sources',
  insights_count: 'Insights captured',
};

function breakdownLabel(key: string): string {
  return BREAKDOWN_LABELS[key] ?? key.replace(/_/g, ' ');
}

export function ReadinessGauge({
  score,
  breakdown,
  className,
}: {
  score: number;
  breakdown: Record<string, number>;
  className?: string;
}) {
  const clamped = Math.min(100, Math.max(0, score));
  const data = [{ name: 'score', value: clamped, fill: 'hsl(var(--chart-1))' }];

  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      className={cn('flex flex-col items-center gap-4', className)}
    >
      <div className="relative h-48 w-48">
        <ResponsiveContainer width="100%" height="100%">
          <RadialBarChart
            cx="50%"
            cy="50%"
            innerRadius="70%"
            outerRadius="100%"
            barSize={12}
            data={data}
            startAngle={90}
            endAngle={-270}
          >
            <PolarAngleAxis type="number" domain={[0, 100]} angleAxisId={0} tick={false} />
            <RadialBar
              background={{ fill: 'hsl(var(--muted))' }}
              dataKey="value"
              cornerRadius={6}
              animationDuration={600}
            />
          </RadialBarChart>
        </ResponsiveContainer>
        <motion.div className="absolute inset-0 flex flex-col items-center justify-center">
          <span className="font-display text-3xl font-semibold text-text-primary">{clamped}</span>
          <span className="text-xs text-text-secondary">Readiness</span>
        </motion.div>
      </div>
      <ul className="w-full space-y-2">
        {Object.entries(breakdown).map(([key, val], i) => (
          <motion.li
            key={key}
            initial={{ opacity: 0, x: -6 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: i * 0.05 }}
            className="flex items-center justify-between text-sm"
          >
            <span className="text-text-secondary">{breakdownLabel(key)}</span>
            <span className="font-medium tabular-nums text-text-primary">{val}</span>
          </motion.li>
        ))}
      </ul>
    </motion.div>
  );
}
