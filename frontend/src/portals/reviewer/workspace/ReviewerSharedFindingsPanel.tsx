import type { DiscoveryState, ReviewDiscussion } from '../../../lib/api';
import { agentLabel } from '../../../components/ui/DiscoveryProvenancePanel';
import { Badge, Card, StrengthBar } from '../../../components/ui';
import { EvidenceAskBubble } from './EvidenceAskBubble';

export function ReviewerSharedFindingsPanel({
  findings,
  conversationSummary,
  discussions,
  coReviewers,
  employeeId,
  conversationId,
  onAskReviewer,
  onAskEmployee,
}: {
  findings: DiscoveryState['shared_findings'];
  conversationSummary: string | null;
  discussions?: ReviewDiscussion[];
  coReviewers?: { reviewer_user_id: number; reviewer_name: string }[];
  employeeId?: number;
  conversationId?: number;
  onAskReviewer?: (targetReviewerUserId: number, body: string, anchorId: string) => Promise<void>;
  onAskEmployee?: (body: string, anchorId: string) => Promise<void>;
}) {
  const threadDiscussions = discussions ?? [];
  const reviewers = coReviewers ?? [];

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
            {findings.map((finding, index) => {
              const anchorId = String(index);
              return (
                <li key={`${finding.turn}-${finding.agent}-${index}`} className="relative rounded-lg border border-border p-4">
                  <div className="mb-2 flex flex-wrap items-center gap-2">
                    <span className="text-xs font-medium text-muted-foreground">Turn {finding.turn}</span>
                    <Badge variant="info">{agentLabel(finding.agent)}</Badge>
                    <span className="text-xs text-muted-foreground">{Math.round(finding.confidence * 100)}% confidence</span>
                    {onAskReviewer && reviewers.length > 0 && (
                      <div className="ml-auto">
                        <EvidenceAskBubble
                          anchorType="finding"
                          anchorId={anchorId}
                          coReviewers={reviewers}
                          employeeId={employeeId}
                          conversationId={conversationId}
                          discussions={threadDiscussions}
                          onAskReviewer={(targetId, body) => onAskReviewer(targetId, body, anchorId)}
                          onAskEmployee={
                            onAskEmployee && employeeId && conversationId
                              ? (body) => onAskEmployee(body, anchorId)
                              : undefined
                          }
                        />
                      </div>
                    )}
                  </div>
                  <p className="m-0 text-sm leading-relaxed text-foreground">{finding.finding}</p>
                  <StrengthBar strength={finding.confidence} className="mt-3" />
                </li>
              );
            })}
          </ul>
        )}
      </Card>
    </div>
  );
}
