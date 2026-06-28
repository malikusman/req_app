import type { DiscoveryState } from '../../../lib/api';
import { agentLabel } from '../../../components/ui/DiscoveryProvenancePanel';
import { Badge, Card, StrengthBar } from '../../../components/ui';

export function ReviewerSharedFindingsPanel({
  findings,
  conversationSummary,
}: {
  findings: DiscoveryState['shared_findings'];
  conversationSummary: string | null;
}) {
  return (
    <div className="space-y-4">
      {conversationSummary && (
        <Card title="Rolling conversation summary">
          <p className="m-0 text-sm leading-relaxed text-foreground">{conversationSummary}</p>
        </Card>
      )}

      <Card title="Agent shared findings">
        {findings.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            No structured findings recorded. Review the transcript directly in Source evidence.
          </p>
        ) : (
          <ul className="m-0 list-none space-y-3 p-0">
            {findings.map((finding, index) => (
              <li key={`${finding.turn}-${finding.agent}-${index}`} className="rounded-lg border border-border p-4">
                <div className="mb-2 flex flex-wrap items-center gap-2">
                  <span className="text-xs font-medium text-muted-foreground">Turn {finding.turn}</span>
                  <Badge variant="info">{agentLabel(finding.agent)}</Badge>
                  <span className="text-xs text-muted-foreground">{Math.round(finding.confidence * 100)}% confidence</span>
                </div>
                <p className="m-0 text-sm leading-relaxed text-foreground">{finding.finding}</p>
                <StrengthBar strength={finding.confidence} className="mt-3" />
              </li>
            ))}
          </ul>
        )}
      </Card>
    </div>
  );
}
