import { Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import { cn } from '../../lib/cn';

export type SimpleBarDatum = {
  name: string;
  value: number;
};

export function SimpleBarChart({
  data,
  emptyLabel = 'No data yet',
  valueSuffix = '',
  height = 220,
  layout = 'vertical',
  className,
}: {
  data: SimpleBarDatum[];
  emptyLabel?: string;
  valueSuffix?: string;
  height?: number;
  layout?: 'vertical' | 'horizontal';
  className?: string;
}) {
  if (!data.length) {
    return <p className="m-0 text-sm text-muted-foreground">{emptyLabel}</p>;
  }

  const isHorizontal = layout === 'horizontal';
  const chartData = data.map((d) => ({
    ...d,
    name: d.name.length > 22 ? `${d.name.slice(0, 20)}…` : d.name,
  }));

  return (
    <div className={cn('w-full min-w-0', className)} style={{ height }}>
      <ResponsiveContainer width="100%" height="100%">
        <BarChart
          data={chartData}
          layout={isHorizontal ? 'vertical' : 'horizontal'}
          margin={{ top: 8, right: 12, left: 4, bottom: 8 }}
        >
          <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" vertical={!isHorizontal} horizontal={isHorizontal} />
          {isHorizontal ? (
            <>
              <XAxis type="number" tick={{ fontSize: 11, fill: 'hsl(var(--muted-foreground))' }} axisLine={false} tickLine={false} />
              <YAxis
                type="category"
                dataKey="name"
                width={96}
                tick={{ fontSize: 11, fill: 'hsl(var(--muted-foreground))' }}
                axisLine={false}
                tickLine={false}
              />
            </>
          ) : (
            <>
              <XAxis
                dataKey="name"
                tick={{ fontSize: 11, fill: 'hsl(var(--muted-foreground))' }}
                axisLine={false}
                tickLine={false}
                interval={0}
                angle={chartData.length > 4 ? -25 : 0}
                textAnchor={chartData.length > 4 ? 'end' : 'middle'}
                height={chartData.length > 4 ? 56 : 30}
              />
              <YAxis tick={{ fontSize: 11, fill: 'hsl(var(--muted-foreground))' }} axisLine={false} tickLine={false} width={36} />
            </>
          )}
          <Tooltip
            cursor={{ fill: 'hsl(var(--muted) / 0.5)' }}
            contentStyle={{
              background: 'hsl(var(--card))',
              border: '1px solid hsl(var(--border))',
              borderRadius: 8,
              fontSize: 12,
            }}
            formatter={(value) => [`${value}${valueSuffix}`, 'Value']}
          />
          <Bar dataKey="value" fill="hsl(var(--chart-1))" radius={[4, 4, 4, 4]} maxBarSize={36} />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
