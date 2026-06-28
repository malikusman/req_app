import type { DiscoveryState } from '../../../lib/api';
import { Badge } from '../../../components/ui/Badge';
import { Card } from '../../../components/ui/Card';

function formatList(value: unknown): string[] {
  if (Array.isArray(value)) return value.map(String).filter(Boolean);
  if (typeof value === 'string' && value.trim()) return [value];
  return [];
}

export function ReviewerEmployeeProfileCard({
  employeeName,
  department,
  profile,
}: {
  employeeName: string | null;
  department: string | null;
  profile: DiscoveryState['profile'];
}) {
  const roleTitle = String(profile.role_title || profile.role || '—');
  const seniority = String(profile.seniority || '—').replace(/_/g, ' ');
  const responsibilities = String(profile.responsibilities || '—');
  const tools = formatList(profile.primary_tools);

  return (
    <Card title={employeeName || 'Employee profile'}>
      <dl className="grid gap-3 text-sm sm:grid-cols-2">
        <div>
          <dt className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Department</dt>
          <dd className="mt-1 text-foreground">{department || String(profile.department || '—')}</dd>
        </div>
        <div>
          <dt className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Seniority</dt>
          <dd className="mt-1 capitalize text-foreground">{seniority}</dd>
        </div>
        <div className="sm:col-span-2">
          <dt className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Role</dt>
          <dd className="mt-1 text-foreground">{roleTitle}</dd>
        </div>
        <div className="sm:col-span-2">
          <dt className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Responsibilities</dt>
          <dd className="mt-1 whitespace-pre-wrap text-foreground">{responsibilities}</dd>
        </div>
        {tools.length > 0 && (
          <div className="sm:col-span-2">
            <dt className="mb-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">Primary tools</dt>
            <dd className="flex flex-wrap gap-1.5">
              {tools.map((tool) => (
                <Badge key={tool} variant="neutral">
                  {tool}
                </Badge>
              ))}
            </dd>
          </div>
        )}
      </dl>
    </Card>
  );
}
