import type { DiscoveryState } from '../../lib/api';
import { Badge } from '../../components/ui';

function agentLabel(id: string): string {
  if (id.startsWith('domain_')) return `Domain · ${id.replace('domain_', '')}`;
  return id.charAt(0).toUpperCase() + id.slice(1);
}

export function DiscoveryAgentPanel({ state }: { state: DiscoveryState }) {
  const required = state.coverage.topics_required ?? [];
  const covered = state.coverage.topics_covered ?? [];

  return (
    <div className="max-h-[480px] space-y-4 overflow-y-auto pr-1">
      <div>
        <p className="m-0 mb-2 text-xs font-medium uppercase tracking-wide text-text-secondary">Agent queue</p>
        <div className="space-y-2">
          {state.agent_queue.map((agent) => {
            const agentState = state.agent_states[agent.id];
            const isActive = state.active_agent_id === agent.id;
            return (
              <div
                key={agent.id}
                className="flex flex-wrap items-center justify-between gap-2 rounded-card border border-border bg-surface-muted px-3 py-2"
              >
                <div>
                  <span className="text-sm font-medium text-text-primary">{agentLabel(agent.id)}</span>
                  <p className="m-0 text-xs text-text-secondary">{agent.reason}</p>
                </div>
                <div className="flex items-center gap-2">
                  {agentState && (
                    <span className="text-xs text-text-secondary">
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
        {state.skipped_agents.length > 0 && (
          <p className="m-0 mt-2 text-xs text-text-secondary">
            Skipped: {state.skipped_agents.map((s) => `${agentLabel(s.id)} (${s.reason})`).join(' · ')}
          </p>
        )}
      </div>

      {required.length > 0 && (
        <div>
          <p className="m-0 mb-2 text-xs font-medium uppercase tracking-wide text-text-secondary">Coverage</p>
          <div className="flex flex-wrap gap-1.5">
            {required.map((topic) => (
              <Badge key={topic} variant={covered.includes(topic) ? 'success' : 'neutral'}>
                {topic.replace(/_/g, ' ')}
              </Badge>
            ))}
          </div>
        </div>
      )}

      {state.last_routing_decision && (
        <div>
          <p className="m-0 mb-1 text-xs font-medium uppercase tracking-wide text-text-secondary">Last routing decision</p>
          <p className="m-0 text-sm text-text-primary">
            <Badge variant="info">{state.last_routing_decision.action}</Badge>{' '}
            {state.last_routing_decision.reason}
          </p>
        </div>
      )}

      {state.conversation_summary && (
        <div>
          <p className="m-0 mb-1 text-xs font-medium uppercase tracking-wide text-text-secondary">Rolling summary</p>
          <p className="m-0 text-sm text-text-secondary">{state.conversation_summary}</p>
        </div>
      )}

      <div>
        <p className="m-0 mb-2 text-xs font-medium uppercase tracking-wide text-text-secondary">
          Shared findings ({state.shared_findings.length})
        </p>
        {state.shared_findings.length === 0 ? (
          <p className="m-0 text-sm text-text-secondary">No findings extracted yet.</p>
        ) : (
          <ul className="m-0 list-none space-y-2 p-0">
            {state.shared_findings.map((f, idx) => (
              <li key={idx} className="rounded-card border border-border bg-surface-muted px-3 py-2">
                <p className="m-0 text-sm text-text-primary">{f.finding}</p>
                <p className="m-0 mt-1 text-xs text-text-secondary">
                  {agentLabel(f.agent)} · turn {f.turn} · confidence {Math.round(f.confidence * 100)}%
                </p>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}
