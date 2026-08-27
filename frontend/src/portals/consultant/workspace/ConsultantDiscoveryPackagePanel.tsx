import { AlertTriangle, Lightbulb, MessageCircleQuestion } from 'lucide-react';
import type { DiscoveryPackage, DiscoveryPackageItem } from '../../../lib/api';
import { Badge, Card, EmptyState } from '../../../components/ui';
import { cn } from '../../../lib/cn';

const IMPACT_TONE: Record<string, 'error' | 'warning' | 'neutral'> = {
  high: 'error',
  medium: 'warning',
  low: 'neutral',
};

function ItemRow({ item, linkedTitle }: { item: DiscoveryPackageItem; linkedTitle?: string | null }) {
  return (
    <li
      className={cn(
        'rounded-lg border border-border bg-muted/30 px-3 py-2',
        item.status === 'rejected' && 'opacity-55'
      )}
    >
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <span className="text-sm font-medium text-foreground">{item.title || 'Untitled'}</span>
        <span className="flex shrink-0 items-center gap-1.5">
          {item.impact && <Badge variant={IMPACT_TONE[item.impact]}>{item.impact} impact</Badge>}
          {item.origin === 'consultant' && <Badge variant="info">yours</Badge>}
          {item.status === 'rejected' && <Badge variant="neutral">rejected</Badge>}
        </span>
      </div>
      <p className="m-0 mt-1 text-sm text-muted-foreground">{item.body}</p>
      {linkedTitle && (
        <p className="m-0 mt-1 text-xs text-muted-foreground">Addresses: {linkedTitle}</p>
      )}
    </li>
  );
}

/**
 * Read-only view of the Discovery handover. Editing the recommendation, amending
 * issues and solutions, and stating what you need to know all arrive with the
 * consultant review work — this shows what the interview produced.
 */
export function ConsultantDiscoveryPackagePanel({
  pkg,
  employeeName,
}: {
  pkg: DiscoveryPackage | null;
  employeeName: string | null;
}) {
  if (!pkg) {
    return (
      <Card title="Discovery handover">
        <EmptyState
          title="No handover yet"
          description="It is assembled when the interview finishes. If the interview has completed, generation may still be running."
        />
      </Card>
    );
  }

  if (pkg.status === 'failed') {
    return (
      <Card title="Discovery handover">
        <p className="m-0 text-sm text-status-error">
          This handover could not be assembled{pkg.error_message ? `: ${pkg.error_message}` : '.'} The
          interview and its transcript are unaffected — use Source evidence in the meantime.
        </p>
      </Card>
    );
  }

  const issueTitleById = new Map(pkg.issues.map((i) => [i.id, i.title]));

  return (
    <Card title="Discovery handover">
      <div className="space-y-5">
        <p className="m-0 -mt-1 text-sm text-muted-foreground">
          What the interview with {employeeName || 'this employee'} concluded · v{pkg.version}
        </p>

        {pkg.built_without_model && (
          <p className="m-0 rounded-lg border border-warning/30 bg-warning/10 px-3 py-2 text-xs text-warning">
            Assembled directly from the interview without a language model, so it carries issues but no
            proposed solutions. Treat the confidence as low.
          </p>
        )}

        <div>
          <p className="m-0 mb-1 text-label-caps text-muted-foreground">Recommendation</p>
          <p className="m-0 text-sm font-medium text-foreground">
            {pkg.recommendation || 'No recommendation was produced.'}
          </p>
          {pkg.recommendation_rationale && (
            <p className="m-0 mt-1 text-sm text-muted-foreground">{pkg.recommendation_rationale}</p>
          )}
          {pkg.confidence != null && (
            <p className="m-0 mt-1.5 text-xs tabular-nums text-muted-foreground">
              Agent confidence {Math.round(pkg.confidence * 100)}%
            </p>
          )}
        </div>

        <div>
          <p className="m-0 mb-2 flex items-center gap-1.5 text-label-caps text-muted-foreground">
            <AlertTriangle className="h-3.5 w-3.5" /> Issues ({pkg.issues.length})
          </p>
          {pkg.issues.length === 0 ? (
            <p className="m-0 text-sm text-muted-foreground">No issues were identified.</p>
          ) : (
            <ul className="m-0 list-none space-y-2 p-0">
              {pkg.issues.map((item) => (
                <ItemRow key={item.id} item={item} />
              ))}
            </ul>
          )}
        </div>

        <div>
          <p className="m-0 mb-2 flex items-center gap-1.5 text-label-caps text-muted-foreground">
            <Lightbulb className="h-3.5 w-3.5" /> Possible solutions ({pkg.solutions.length})
          </p>
          {pkg.solutions.length === 0 ? (
            <p className="m-0 text-sm text-muted-foreground">None proposed.</p>
          ) : (
            <ul className="m-0 list-none space-y-2 p-0">
              {pkg.solutions.map((item) => (
                <ItemRow
                  key={item.id}
                  item={item}
                  linkedTitle={item.linked_item_id ? issueTitleById.get(item.linked_item_id) : null}
                />
              ))}
            </ul>
          )}
        </div>

        <div>
          <p className="m-0 mb-2 flex items-center gap-1.5 text-label-caps text-muted-foreground">
            <MessageCircleQuestion className="h-3.5 w-3.5" /> Questions it intends to ask next (
            {pkg.followup_questions.length})
          </p>
          {pkg.followup_questions.length === 0 ? (
            <p className="m-0 text-sm text-muted-foreground">None drafted.</p>
          ) : (
            <ol className="m-0 list-none space-y-2 p-0">
              {pkg.followup_questions.map((q, index) => (
                <li key={q.id} className="rounded-lg border border-border bg-muted/30 px-3 py-2">
                  <div className="flex flex-wrap items-baseline justify-between gap-2">
                    <span className="text-sm text-foreground">{q.body}</span>
                    <span className="flex shrink-0 items-center gap-1.5">
                      {index === 0 && q.status !== 'sent' && q.status !== 'answered' && (
                        <Badge variant="info">next</Badge>
                      )}
                      {q.from_parked_aside && <Badge variant="neutral">from an aside</Badge>}
                      {q.status !== 'drafted' && <Badge variant="neutral">{q.status}</Badge>}
                    </span>
                  </div>
                  {q.rationale && (
                    <p className="m-0 mt-1 text-xs text-muted-foreground">{q.rationale}</p>
                  )}
                </li>
              ))}
            </ol>
          )}
        </div>
      </div>
    </Card>
  );
}
