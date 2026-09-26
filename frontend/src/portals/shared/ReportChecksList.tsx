import { Check } from 'lucide-react';
import type { ReportCheck } from '../../lib/api';
import { Badge } from '../../components/ui';

/**
 * The rule checks a Stage 1 report must keep before approval (Reports::Critic),
 * blocking ones first. Shared by the consultant's submit step and the platform
 * approval dialog, so both see the same list in the same words.
 */
export function ReportChecksList({ checks }: { checks: ReportCheck[] }) {
  if (checks.length === 0) {
    return (
      <p className="m-0 flex items-center gap-2 text-sm text-foreground">
        <Check className="h-4 w-4 text-status-success" />
        Passes every check.
      </p>
    );
  }
  const ordered = [...checks].sort((a, b) => (a.severity === b.severity ? 0 : a.severity === 'block' ? -1 : 1));
  return (
    <ul className="m-0 list-none space-y-2 p-0">
      {ordered.map((c) => (
        <li key={`${c.code}-${c.message}`} className="flex items-start gap-3 text-sm">
          <Badge variant={c.severity === 'block' ? 'error' : 'warning'} className="mt-0.5 shrink-0">
            {c.severity === 'block' ? 'Must fix' : 'Check'}
          </Badge>
          <span className="text-foreground">{c.message}</span>
        </li>
      ))}
    </ul>
  );
}
