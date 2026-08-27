import type { DiscoveryState, ReviewDiscussion } from '../../../lib/api';
import { agentLabel } from '../../../components/ui/DiscoveryProvenancePanel';
import { Badge, Card, StrengthBar } from '../../../components/ui';
import { EvidenceAskBubble } from './EvidenceAskBubble';
import { ReviewDiscussionThreadList } from './ReviewDiscussionThreadList';

export function ConsultantSharedFindingsPanel({
  findings,
  conversationSummary,
  discussions,
  coConsultants,
  employeeId,
  conversationId,
  currentConsultantUserId,
  onAskConsultant,
  onAskEmployee,
  onReplyDiscussion,
  onResolveDiscussion,
  readOnly,
}: {
  findings: DiscoveryState['shared_findings'];
  conversationSummary: string | null;
  discussions?: ReviewDiscussion[];
  coConsultants?: { consultant_user_id: number; consultant_name: string }[];
  employeeId?: number;
  conversationId?: number;
  currentConsultantUserId?: number | null;
  onAskConsultant?: (targetConsultantUserId: number, body: string, anchorId: string) => Promise<void>;
  onAskEmployee?: (body: string, anchorId: string) => Promise<void>;
  onReplyDiscussion?: (discussionId: number, body: string) => Promise<void>;
  onResolveDiscussion?: (discussionId: number) => Promise<void>;
  readOnly?: boolean;
}) {
  const threadDiscussions = discussions ?? [];
  const consultants = coConsultants ?? [];
  const findingThreads = threadDiscussions.filter((d) => d.anchor_type === 'finding');

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
                    {onAskConsultant && consultants.length > 0 && (
                      <div className="ml-auto">
                        <EvidenceAskBubble
                          anchorType="finding"
                          anchorId={anchorId}
                          coConsultants={consultants}
                          employeeId={employeeId}
                          conversationId={conversationId}
                          discussions={threadDiscussions}
                          onAskConsultant={(targetId, body) => onAskConsultant(targetId, body, anchorId)}
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

      {onReplyDiscussion && onResolveDiscussion && (
        <Card title="Finding discussions">
          <ReviewDiscussionThreadList
            discussions={findingThreads}
            currentConsultantUserId={currentConsultantUserId ?? null}
            onReply={onReplyDiscussion}
            onResolve={onResolveDiscussion}
            disabled={readOnly}
            emptyMessage="No discussions on findings yet. Use the + icon on a finding to ask a question."
          />
        </Card>
      )}
    </div>
  );
}
