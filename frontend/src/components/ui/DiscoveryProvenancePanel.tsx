import type { DiscoveryProvenanceEntry, DiscoveryState } from '../../lib/api';
import { Badge } from './Badge';
import { cn } from '../../lib/cn';

const SLOT_SEP = '::';

/** "friction::Invoicing" -> { label: "friction", area: "Invoicing" } */
function parseSlotKey(key: string): { label: string; area: string | null } {
  const [slot, area] = key.split(SLOT_SEP);
  return { label: slot.replace(/_/g, ' '), area: area ?? null };
}

export function agentLabel(id: string): string {
  // Phases of the interview, not specialists: the specialist queue is retired.
  const labels: Record<string, string> = {
    orient: 'Orienting',
    branch: 'Exploring',
    close: 'Closing',
  };
  if (labels[id]) return labels[id];
  if (id.startsWith('domain_')) return `Domain · ${id.replace('domain_', '')}`;
  return id.charAt(0).toUpperCase() + id.slice(1);
}

const CLOSE_REASON_LABEL: Record<string, { text: string; tone: 'success' | 'warning' | 'neutral' }> = {
  dossier_complete: { text: 'Ended with everything covered', tone: 'success' },
  employee_ended: { text: 'Employee asked to stop', tone: 'neutral' },
  stalled: { text: 'Ended — conversation had stopped progressing', tone: 'warning' },
  ceiling: { text: 'Ended at the question ceiling', tone: 'warning' },
};

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
  const areas = state?.role_areas ?? [];
  const slots = state?.slots ?? {};
  const parked = state?.parked ?? [];
  const slotKeys = Object.keys(slots);
  const closeReason = state?.close_reason ? CLOSE_REASON_LABEL[state.close_reason] : null;

  return (
    <div className={cn('max-h-[520px] space-y-5 overflow-y-auto pr-1', className)}>
      <div>
        <p className="m-0 mb-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">
          Question timeline
        </p>
        {provenance.length === 0 ? (
          <p className="m-0 text-sm text-muted-foreground">
            Question provenance appears as the interview runs.
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

      {closeReason && (
        <div>
          <p className="m-0 mb-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">
            How it ended
          </p>
          <Badge variant={closeReason.tone}>{closeReason.text}</Badge>
        </div>
      )}

      {areas.length > 0 && (
        <div>
          <p className="m-0 mb-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">
            Their role areas
          </p>
          <div className="flex flex-wrap gap-1.5">
            {areas.map((area) => (
              <Badge key={area.name} variant="info">
                {area.name}
              </Badge>
            ))}
          </div>
        </div>
      )}

      {slotKeys.length > 0 && (
        <div>
          <p className="m-0 mb-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">
            What the interview learned
          </p>
          <div className="space-y-2">
            {slotKeys.map((key) => {
              const slot = slots[key];
              const { label, area } = parseSlotKey(key);
              return (
                <div
                  key={key}
                  className="rounded-lg border border-border bg-muted/40 px-3 py-2"
                >
                  <div className="flex flex-wrap items-baseline justify-between gap-2">
                    <span className="text-sm font-medium text-foreground">
                      {label}
                      {area && <span className="text-muted-foreground"> · {area}</span>}
                    </span>
                    <span className="shrink-0 text-xs tabular-nums text-muted-foreground">
                      {Math.round(slot.confidence * 100)}% · Q{slot.turn}
                    </span>
                  </div>
                  {slot.value && (
                    <p className="m-0 mt-1 line-clamp-2 text-xs text-muted-foreground">{slot.value}</p>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      )}

      {parked.length > 0 && (
        <div>
          <p className="m-0 mb-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">
            Captured, not chased
          </p>
          <ul className="m-0 list-none space-y-1 p-0">
            {parked.map((item) => (
              <li key={`${item.turn}-${item.note}`} className="text-xs text-muted-foreground">
                <span className="tabular-nums">Q{item.turn}</span>
                {item.area && <span> · {item.area}</span>} — {item.note}
              </li>
            ))}
          </ul>
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
