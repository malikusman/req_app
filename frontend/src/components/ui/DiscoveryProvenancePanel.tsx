import type { DiscoveryProvenanceEntry, DiscoveryState } from '../../lib/api';
import { Badge } from './Badge';
import { cn } from '../../lib/cn';

export function agentLabel(id: string): string {
  if (id.startsWith('domain_')) return `Domain · ${id.replace('domain_', '')}`;
  return id.charAt(0).toUpperCase() + id.slice(1);
}

function actionVariant(action: string | undefined): 'info' | 'success' | 'warning' | 'neutral' {
  if (action === 'handoff') return 'warning';
  if (action === 'close') return 'success';
  if (action === 'continue') return 'info';
  return 'neutral';
}

export function DiscoveryProvenancePanel({
  state,
  provenance,
  selectedMessageId,
  onSelectMessage,
  className,
}: {
  state?: DiscoveryState | null;
  provenance: DiscoveryProvenanceEntry[];
  selectedMessageId?: number | null;
  onSelectMessage?: (messageId: number) => void;
  className?: string;
}) {
  const required = state?.coverage.topics_required ?? [];
  const covered = state?.coverage.topics_covered ?? [];
  const hasQueue = (state?.agent_queue.length ?? 0) > 0;

  return (
    <div className={cn('max-h-[520px] space-y-5 overflow-y-auto pr-1', className)}>
      <div>
        <p className="m-0 mb-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">
          Question timeline
        </p>
        {provenance.length === 0 ? (
          <p className="m-0 text-sm text-muted-foreground">
            {hasQueue
              ? 'Agent routing metadata appears on new discovery questions.'
              : 'Multi-agent provenance appears when routing is enabled for this company.'}
          </p>
        ) : (
          <ol className="m-0 list-none space-y-2 p-0">
            {provenance.map((entry, index) => {
              const selected = selectedMessageId === entry.message_id;
              const action = entry.routing_decision?.action;
              return (
                <li key={entry.message_id}>
                  <button
                    type="button"
                    onClick={() => onSelectMessage?.(entry.message_id)}
                    className={cn(
                      'w-full rounded-lg border px-3 py-2 text-left transition-colors',
                      selected
                        ? 'border-primary bg-primary/5'
                        : 'border-border bg-muted/40 hover:bg-muted/70'
                    )}
                  >
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="text-xs font-medium text-muted-foreground">Q{index + 1}</span>
                      {entry.agent_id && (
                        <Badge variant="info">{agentLabel(entry.agent_id)}</Badge>
                      )}
                      {action && <Badge variant={actionVariant(action)}>{action}</Badge>}
                    </div>
                    <p className="m-0 mt-1 line-clamp-2 text-sm text-foreground">{entry.body_preview}</p>
                    {entry.routing_decision?.reason && (
                      <p className="m-0 mt-1 text-xs text-muted-foreground">{entry.routing_decision.reason}</p>
                    )}
                  </button>
                </li>
              );
            })}
          </ol>
        )}
      </div>

      {hasQueue && state && (
        <div>
          <p className="m-0 mb-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">Agent queue</p>
          <div className="space-y-2">
            {state.agent_queue.map((agent) => {
              const agentState = state.agent_states[agent.id];
              const isActive = state.active_agent_id === agent.id;
              return (
                <div
                  key={agent.id}
                  className="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-border bg-muted/40 px-3 py-2"
                >
                  <div className="min-w-0">
                    <span className="text-sm font-medium text-foreground">{agentLabel(agent.id)}</span>
                    <p className="m-0 truncate text-xs text-muted-foreground">{agent.reason}</p>
                  </div>
                  <div className="flex shrink-0 items-center gap-2">
                    {agentState && (
                      <span className="text-xs text-muted-foreground">
                        {agentState.questions_asked}/{agentState.question_budget} q
                      </span>
                    )}
                    {isActive ? (
                      <Badge variant="info">active</Badge>
                    ) : agentState?.status === 'complete' ? (
                      <Badge variant="success">done</Badge>
                    ) : (
                      <Badge variant="neutral">queued</Badge>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {required.length > 0 && state && (
        <div>
          <p className="m-0 mb-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">Coverage</p>
          <div className="flex flex-wrap gap-1.5">
            {required.map((topic) => (
              <Badge key={topic} variant={covered.includes(topic) ? 'success' : 'neutral'}>
                {topic.replace(/_/g, ' ')}
              </Badge>
            ))}
          </div>
        </div>
      )}

      {state?.conversation_summary && (
        <div>
          <p className="m-0 mb-1 text-xs font-medium uppercase tracking-wide text-muted-foreground">
            Rolling summary
          </p>
          <p className="m-0 text-sm text-muted-foreground">{state.conversation_summary}</p>
        </div>
      )}
    </div>
  );
}
