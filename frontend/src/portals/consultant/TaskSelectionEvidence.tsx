import type { AnnualWorkload, EffortRange, Proposal, Relationship, ReviewParticipant, TaskSource } from '../../lib/taskSelection';

export const words = (value: string) => value.replaceAll('_', ' ');

export function TextList({ items }: { items: string[] }) {
  return items.length ? <ul className="list-disc space-y-1 pl-5">{items.map((item, index) => <li key={index}>{item}</li>)}</ul> : <p>None recorded.</p>;
}

export function workload(value?: AnnualWorkload) {
  if (!value) return 'No supported annual range';
  const hours = value.annual_hours_min != null && value.annual_hours_max != null
    ? `${value.annual_hours_min}–${value.annual_hours_max} hours/year · ` : '';
  const labels: Record<string, string> = {
    unknown: 'No estimate yet', unknown_active_effort: 'Time estimate not yet confirmed',
    withheld_possible_overlap: 'Estimate withheld because work may overlap',
    withheld_shared_evidence: 'Estimate withheld because tasks share evidence',
    reported_active_workload: 'Reported active work', conditional_consultant_assumption: 'Based on consultant assumptions',
    unresolved_overlap: 'Overlap needs review',
  };
  return hours + (labels[value.status] ?? words(value.status));
}

export function sourceLabel(source: TaskSource) {
  return `${source.name} · source #${source.id} v${source.version}`;
}

function range(value: EffortRange) {
  if (value.min == null) return 'unknown';
  return `${value.min}${value.max != null && value.max !== value.min ? `–${value.max}` : ''} ${words(value.unit ?? '')}`;
}

export function ProposalEvidence({ proposal, sources }: { proposal: Proposal; sources: TaskSource[] }) {
  const assessment = proposal.assessment;
  return <details className="space-y-2">
    <summary className="cursor-pointer font-medium">{proposal.rank ? `Rank ${proposal.rank}` : 'Outside shortlist'} · {proposal.title}</summary>
    <p>{words(proposal.disposition)} · {proposal.priority} priority · {proposal.confidence} confidence · score {proposal.score} · cluster revision {proposal.process_cluster_revision_number}</p>
    <p>{proposal.disposition_reason}</p>
    <p><strong>Reported workload</strong> {workload(assessment.observed_workload)}</p>
    {assessment.possible_released_effort && <p><strong>Possible released effort</strong> Up to {assessment.possible_released_effort.annual_hours_upper_bound} hours/year. {assessment.possible_released_effort.basis}</p>}
    {!!assessment.potential_overlap_cluster_ids.length && <p className="text-warning">Potential overlap with clusters {assessment.potential_overlap_cluster_ids.join(', ')} needs review.</p>}
    <h4 className="font-semibold">Risks</h4><TextList items={assessment.risks} />
    <h4 className="font-semibold">Unknowns</h4><TextList items={assessment.unknowns} />
    <h4 className="font-semibold">Suggested objectives</h4><TextList items={assessment.deep_dive_objectives} />
    <h4 className="font-semibold">Evidence and effort observations</h4>
    {sources.filter(source => proposal.source_ids.includes(source.id)).map(source => {
      const evidence = assessment.evidence_sources.find(item => item.task_source_id === source.id);
      return <div className="rounded-md border border-border p-2" key={source.id}>
        <p>{sourceLabel(source)} · conversation #{source.conversation_id}{source.finding_id ? ` · finding #${source.finding_id}` : ''}</p>
        {evidence && <p>Reported fields {evidence.reported_fields.map(words).join(', ') || 'none'}{evidence.conflicting_fields.length ? ` · conflicting fields ${evidence.conflicting_fields.map(words).join(', ')}` : ''}</p>}
        {source.effort_observations.map((item, index) => <p key={index}>
          {item.scope} · {item.effort_type} · {range(item.frequency)} · {range(item.duration)} · {workload({ ...item, status: item.calculation_reason ?? 'reported' })}
        </p>)}
      </div>;
    })}
  </details>;
}

export function unresolvedRelationship(relationship: Relationship) {
  return relationship.classification ? relationship.classification === 'UNRESOLVED' : relationship.kind === 'uncertain';
}

export function RelationshipEvidence({ relationship, sources, people }: {
  relationship: Relationship; sources: TaskSource[]; people: ReviewParticipant[];
}) {
  const current = relationship.current_clarification_request;
  const request = current ?? relationship.clarification_request;
  const unresolved = unresolvedRelationship(relationship);
  const checks = request?.missing_evidence ?? relationship.missing_evidence ?? [
    'Compare what starts each workflow, what it produces, and where the work is handed off.',
    'Confirm which steps and workload are shared and which are performed separately.',
  ];
  const classification = relationship.classification ?? relationship.kind ?? 'UNRESOLVED';
  const labels: Record<string, string> = {
    SHARED_IDENTICAL: 'Same reported work', SHARED_VARIANT: 'Different versions of the same work',
    DISTINCT: 'Distinct work', UNRESOLVED: 'Possible overlap', uncertain: 'Possible overlap',
  };
  return <details className="space-y-2 rounded-md border border-border p-3 text-sm">
    <summary className="cursor-pointer font-semibold">{request ? 'Clarification · ' : ''}{labels[classification] ?? words(classification)}</summary>
    <ul className="space-y-1">
      {relationship.source_ids.map(id => {
        const source = sources.find(item => item.id === id);
        if (!source) return null;
        const person = people.find(item => item.id === source.employee_id);
        return <li key={id}><strong>{source.name}</strong> · {person?.name || `Employee #${source.employee_id}`} <span className="text-muted-foreground">(Discovery source #{source.id})</span></li>;
      })}
    </ul>
    <p>{relationship.rationale}</p>
    {request && <p className="font-semibold">{current ? 'Current clarification' : 'Clarification at time of run'} · {request.status}</p>}
    {(unresolved || request) && <><h4 className="font-medium">What to verify</h4><TextList items={checks} /></>}
    {request?.why_it_matters?.length ? <>
      <h4 className="font-medium">Why it matters</h4><TextList items={request.why_it_matters} />
    </> : null}
    {request?.unknowns?.length ? <><h4 className="font-medium">Unknowns</h4><TextList items={request.unknowns} /></> : null}
  </details>;
}
