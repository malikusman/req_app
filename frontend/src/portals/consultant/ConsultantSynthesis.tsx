import { useCallback, useEffect, useState, type ReactNode } from 'react';
import { Link, useParams } from 'react-router-dom';
import { AlertTriangle, ArrowLeft, Check, RefreshCw } from 'lucide-react';
import {
  api,
  type ConsultantSynthesis as Payload,
  type OperatingPicture,
  type SynthesisAction,
  type SynthesisCluster,
  type SynthesisOpportunity,
  type SynthesisPair,
  type SynthesisRootCause,
  type SynthesisValidation,
} from '../../lib/api';
import { useConsultantToken } from '../../lib/auth';
import { Badge, Button, Card, Input, PageHeader, Select, StatCard, Tabs, Textarea } from '../../components/ui';

type Decide = (action: SynthesisAction, subjectId: number | undefined, rationale: string, details?: Record<string, unknown>) => Promise<boolean>;

const humanise = (s: string | null | undefined) => (s ?? '').toLowerCase().replace(/_/g, ' ');
const hours = (min?: number | null, max?: number | null) =>
  min == null || max == null ? '—' : min === max ? `${Math.round(min)} h/yr` : `${Math.round(min)}–${Math.round(max)} h/yr`;

const STATE_TEXT: Record<Payload['status'], string> = {
  not_started: 'Synthesis has not run yet. It starts on its own once interview findings or a leadership context exist.',
  queued: 'New evidence arrived — a run is queued.',
  running: 'Synthesis is running.',
  failed: 'The last run failed. The evidence is safe; run it again.',
  stale: 'New evidence has arrived since this synthesis. Run it again to include it.',
  needs_review: 'Items below are waiting on you. Nothing here reaches the client until you approve it and release a report.',
  approved: 'Everything current has been decided.',
};

const VERDICT: Record<SynthesisValidation['relationship'], { label: string; variant: 'success' | 'info' | 'neutral' | 'warning' }> = {
  SUPPORTED: { label: 'Staff evidence supports it', variant: 'success' },
  PARTLY_SUPPORTED: { label: 'Partly supported', variant: 'info' },
  NOT_YET_OBSERVED: { label: 'Not yet observed', variant: 'neutral' },
  POINTS_ELSEWHERE: { label: 'Evidence points elsewhere', variant: 'warning' },
};

const LEVELS = ['SHARED_TASK', 'PROCESS', 'DEPARTMENT', 'CROSS_DEPARTMENT', 'COMPANY_WIDE'];
const NEXT_ACTIONS = ['DEEP_DIVE', 'DIRECT_FINDING', 'CLARIFY', 'TECHNOLOGY_REVIEW', 'DEFER', 'NOT_RECOMMENDED'];
const CATEGORIES = ['PROCESS', 'MANAGEMENT', 'REPORTING', 'SYSTEMS', 'INTEGRATION', 'DATA', 'TRAINING', 'CHANGE', 'GOVERNANCE', 'AI', 'AUTOMATION', 'RISK', 'HYBRID'];

/**
 * Consolidation and synthesis for one company (Doc 10 §17): what different
 * people described that is the same work, what it costs once counted once,
 * whether leadership's concerns are borne out by staff evidence, and the
 * opportunities above any one task. Consultants only — the client sees only
 * what is approved here, inside a released report.
 */
export function ConsultantSynthesis() {
  const { companyId = '' } = useParams();
  const id = Number(companyId);
  const token = useConsultantToken();
  const [data, setData] = useState<Payload | null>(null);
  const [error, setError] = useState('');
  const [tab, setTab] = useState('work');
  const [running, setRunning] = useState(false);

  useEffect(() => {
    if (!token) return;
    api.consultantSynthesis(token, id).then(setData).catch((e) => setError(e instanceof Error ? e.message : 'Failed to load'));
  }, [token, id]);

  const decide: Decide = useCallback(
    async (action, subjectId, rationale, details) => {
      if (!token) return false;
      setError('');
      try {
        setData(await api.consultantSynthesisDecide(token, id, { action, subjectId, rationale, details }));
        return true;
      } catch (e) {
        setError(e instanceof Error ? e.message : 'That did not work');
        return false;
      }
    },
    [token, id]
  );

  const runAgain = async () => {
    if (!token) return;
    setRunning(true);
    try {
      setData(await api.consultantSynthesisRun(token, id));
    } catch (e) {
      setError(e instanceof Error ? e.message : 'That did not work');
    } finally {
      setRunning(false);
    }
  };

  const review = data?.review;
  return (
    <div className="space-y-6">
      <Link to={`/consultant/companies/${companyId}`} className="inline-flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground">
        <ArrowLeft className="h-4 w-4" /> Company overview
      </Link>
      <PageHeader
        title="Synthesis"
        description="Shared work counted once, leadership's view against staff evidence, and opportunities above any one task."
        actions={
          <Button variant="secondary" icon={<RefreshCw className="h-4 w-4" />} loading={running} onClick={() => void runAgain()}>
            Run again
          </Button>
        }
      />
      {/* Two pages group shared work until the engines are one (docs/CONSOLIDATION_ENGINES.md). */}
      <p className="m-0 text-sm text-muted-foreground">
        This decides what goes in the report. To choose what to investigate in deep dives, see{' '}
        <Link className="font-medium text-primary underline" to={`/consultant/companies/${companyId}/task-selection`}>
          Task selection
        </Link>
        .
      </p>
      {error && <p className="m-0 rounded-md bg-destructive/10 px-3 py-2 text-sm text-destructive">{error}</p>}
      {!data ? (
        <p className="text-sm text-muted-foreground">Loading…</p>
      ) : (
        <>
          <p
            data-testid="synthesis-status"
            className={`m-0 rounded-md px-3 py-2 text-sm ${data.status === 'stale' || data.status === 'failed' ? 'bg-status-warningBg' : 'bg-muted/40 text-muted-foreground'}`}
          >
            {STATE_TEXT[data.status]}
            {data.run && ` Version ${data.run.version}${data.run.status === 'PARTIAL' ? ' — the model step was unavailable, so findings and clusters passed forward unsynthesised' : ''}.`}
            {data.run?.queued && ' A new run is queued.'}
          </p>
          {review && (
            <div className="grid gap-3 sm:grid-cols-3 lg:grid-cols-6">
              <StatCard label="Clusters to confirm" value={review.clusters} />
              <StatCard label="Pairs to settle" value={review.pairs} />
              <StatCard label="Leadership verdicts" value={review.validations} />
              <StatCard label="Opportunities" value={review.opportunities} />
              <StatCard label="Root causes" value={review.root_causes} />
              <StatCard label="Picture" value={review.operating_picture ? 'To approve' : '—'} />
            </div>
          )}
          {data.run && data.run.coverage_notes.length > 0 && (
            <Card title="Coverage">
              <ul className="m-0 list-disc space-y-1 pl-5 text-sm text-muted-foreground">
                {data.run.coverage_notes.map((n, i) => (
                  <li key={i}>{n.note}</li>
                ))}
              </ul>
            </Card>
          )}
          <Tabs
            value={tab}
            onChange={setTab}
            tabs={[
              { value: 'work', label: `Shared work (${data.clusters.length})` },
              { value: 'leadership', label: `Leadership vs evidence (${data.validations.length})` },
              { value: 'opportunities', label: `Opportunities (${data.opportunities.length})` },
              { value: 'picture', label: 'How the business runs' },
            ]}
          />
          {tab === 'work' && <SharedWork data={data} decide={decide} />}
          {tab === 'leadership' && <Leadership data={data} decide={decide} />}
          {tab === 'opportunities' && <Opportunities data={data} decide={decide} />}
          {tab === 'picture' && <Picture data={data} decide={decide} />}
        </>
      )}
    </div>
  );
}

/** An action that needs a reason: the first click asks for it. */
function DecisionButton({
  label,
  onDecide,
  variant = 'secondary',
  extra,
  disabled,
}: {
  label: string;
  onDecide: (rationale: string) => Promise<boolean>;
  variant?: 'primary' | 'secondary' | 'danger';
  extra?: ReactNode;
  disabled?: boolean;
}) {
  const [open, setOpen] = useState(false);
  const [rationale, setRationale] = useState('');
  const [busy, setBusy] = useState(false);
  if (!open) {
    return (
      <Button size="sm" variant={variant} disabled={disabled} onClick={() => setOpen(true)}>
        {label}
      </Button>
    );
  }
  return (
    <div className="w-full space-y-2 rounded-md border border-border p-3">
      {extra}
      <Input label={`Why — ${label.toLowerCase()}`} value={rationale} onChange={(e) => setRationale(e.target.value)} placeholder="Your reason is kept with the decision" />
      <div className="flex gap-2">
        <Button
          size="sm"
          disabled={!rationale.trim()}
          loading={busy}
          onClick={async () => {
            setBusy(true);
            const ok = await onDecide(rationale.trim());
            setBusy(false);
            if (ok) {
              setOpen(false);
              setRationale('');
            }
          }}
        >
          {label}
        </Button>
        <Button size="sm" variant="secondary" onClick={() => setOpen(false)}>
          Cancel
        </Button>
      </div>
    </div>
  );
}

function SharedWork({ data, decide }: { data: Payload; decide: Decide }) {
  return (
    <div className="space-y-4">
      {data.pairs_to_review.length > 0 && (
        <Card title="Pairs the model couldn't settle">
          <div className="space-y-4">
            {data.pairs_to_review.map((p) => (
              <PairRow key={p.id} pair={p} decide={decide} />
            ))}
          </div>
        </Card>
      )}
      {data.run && data.run.suggested_additions.length > 0 && (
        <Card title="Suggested additions to clusters you confirmed">
          <div className="space-y-3">
            {data.run.suggested_additions.map((s) => {
              const cluster = data.clusters.find((c) => c.key === s.cluster_key);
              if (!cluster) return null;
              return (
                <div key={`${s.cluster_key}-${s.finding_id}`} className="flex flex-wrap items-center gap-3 text-sm">
                  <span className="min-w-0 flex-1">
                    <strong>{s.finding.title}</strong> ({[s.finding.role, s.finding.department].filter(Boolean).join(', ')}) may belong in{' '}
                    <strong>{cluster.name}</strong>
                    {s.rationale ? ` — ${s.rationale}` : ''}
                  </span>
                  <DecisionButton label="Add to cluster" onDecide={(r) => decide('MERGE_CLUSTERS', cluster.id, r, { finding_ids: [s.finding_id] })} />
                </div>
              );
            })}
          </div>
        </Card>
      )}
      {data.clusters.length === 0 && (
        <Card>
          <p className="m-0 text-sm text-muted-foreground">No shared work found yet. Each finding stands on its own.</p>
        </Card>
      )}
      {data.clusters.map((c) => (
        <ClusterCard key={c.id} cluster={c} decide={decide} />
      ))}
    </div>
  );
}

function PairRow({ pair, decide }: { pair: SynthesisPair; decide: Decide }) {
  const side = (m: SynthesisPair['a']) => (
    <div className="min-w-0 flex-1 rounded-md bg-muted/40 p-2 text-sm">
      <p className="m-0 font-medium">{m.title}</p>
      <p className="m-0 text-muted-foreground">
        {[m.role, m.department].filter(Boolean).join(', ')} · {hours(m.hours_min, m.hours_max)}
      </p>
    </div>
  );
  return (
    <div className="space-y-2" data-testid="pair-to-review">
      <div className="flex flex-col gap-2 sm:flex-row">
        {side(pair.a)}
        {side(pair.b)}
      </div>
      <p className="m-0 text-sm text-muted-foreground">
        {pair.origin === 'FALLBACK' ? 'Not classified — kept separate until you decide.' : `${humanise(pair.relationship_type)}: ${pair.rationale ?? ''}`}
        {pair.clarification ? ` Ask: ${pair.clarification}` : ''}
      </p>
      <div className="flex flex-wrap gap-2">
        <DecisionButton
          label="Same work, each person's hours count"
          onDecide={(r) => decide('CLASSIFY_PAIR', pair.id, r, { relationship_type: 'SAME_PROCESS', same_execution: 'NO', together: true })}
        />
        <DecisionButton
          label="Same work, counted once"
          onDecide={(r) => decide('CLASSIFY_PAIR', pair.id, r, { relationship_type: 'SAME_PROCESS', same_execution: 'YES', together: true })}
        />
        <DecisionButton
          label="Stages of one process"
          onDecide={(r) => decide('CLASSIFY_PAIR', pair.id, r, { relationship_type: 'PROCESS_STAGE', same_execution: 'NO', together: true })}
        />
        <DecisionButton
          label="Keep separate"
          onDecide={(r) => decide('CLASSIFY_PAIR', pair.id, r, { relationship_type: 'INDEPENDENT', same_execution: 'NO', together: false })}
        />
      </div>
    </div>
  );
}

function ClusterCard({ cluster: c, decide }: { cluster: SynthesisCluster; decide: Decide }) {
  const [splitOff, setSplitOff] = useState<number[]>([]);
  const [min, setMin] = useState('');
  const [max, setMax] = useState('');
  const e = c.effort;
  return (
    <Card
      title={c.name}
      action={
        <div className="flex flex-wrap items-center gap-2">
          <Badge variant={c.status === 'APPROVED' ? 'success' : 'info'}>{c.status === 'APPROVED' ? 'Confirmed' : 'Proposed'}</Badge>
          {c.single_member && <Badge variant="warning">One person</Badge>}
          {e?.double_count_warning && <Badge variant="warning">Double-count warning</Badge>}
        </div>
      }
    >
      <div className="space-y-4" data-testid="cluster-card">
        <p className="m-0 text-sm text-muted-foreground">
          {humanise(c.type)} · {c.departments.join(', ') || 'department not recorded'} · {c.confidence ? `${humanise(c.confidence)} confidence` : ''}
        </p>
        {c.why && <p className="m-0 text-sm">Why grouped: {c.why}</p>}
        {c.single_member && (
          <p className="m-0 flex items-start gap-2 rounded-md bg-status-warningBg px-3 py-2 text-sm">
            <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" /> Everything in this cluster comes from one person, so anything said about it describes them. Review before release.
          </p>
        )}
        <ul className="m-0 space-y-1 pl-0 text-sm">
          {c.members.map((m) => (
            <li key={m.finding_id} className="flex flex-wrap items-center gap-2 list-none">
              <input
                type="checkbox"
                aria-label={`Split off ${m.title}`}
                checked={splitOff.includes(m.finding_id)}
                onChange={(ev) =>
                  setSplitOff((prev) => (ev.target.checked ? [...prev, m.finding_id] : prev.filter((x) => x !== m.finding_id)))
                }
              />
              <span className="font-medium">{m.title}</span>
              <span className="text-muted-foreground">{[m.role, m.department].filter(Boolean).join(', ')}</span>
              <span className="text-muted-foreground">{hours(m.hours_min, m.hours_max)}</span>
              {m.variant && <Badge variant="neutral">{m.variant}</Badge>}
              {m.stale && <Badge variant="warning">Changed since grouped</Badge>}
            </li>
          ))}
        </ul>
        {e && (
          <div className="grid gap-2 text-sm sm:grid-cols-3">
            <div>
              <p className="m-0 text-muted-foreground">Everyone's own estimates</p>
              <p className="m-0 font-medium">{hours(e.raw_min, e.raw_max)}</p>
            </div>
            <div>
              <p className="m-0 text-muted-foreground">Counted once{e.overridden ? ' (your figure)' : ''}</p>
              <p className="m-0 font-medium" data-testid="cluster-dedup">{hours(e.hours_min, e.hours_max)}</p>
            </div>
            <div>
              <p className="m-0 text-muted-foreground">A deep dive would need</p>
              <p className="m-0 font-medium">
                {c.sampling.recommended.map((r) => r.role).filter(Boolean).join('; ') || '—'}
                {c.sampling.not_needed > 0 ? ` (${c.sampling.not_needed} not needed)` : ''}
              </p>
            </div>
          </div>
        )}
        {e?.warning_reason && <p className="m-0 text-sm text-muted-foreground">{e.warning_reason}</p>}
        {e && e.adjustments.length > 0 && (
          <details className="text-sm text-muted-foreground">
            <summary>What was adjusted</summary>
            <ul className="m-0 mt-1 list-disc pl-5">
              {e.adjustments.map((a, i) => (
                <li key={i}>{a.reason}</li>
              ))}
            </ul>
          </details>
        )}
        <div className="flex flex-wrap gap-2">
          {c.status !== 'APPROVED' && (
            <DecisionButton label="Confirm" variant="primary" onDecide={(r) => decide('APPROVE_CLUSTER', c.id, r)} />
          )}
          <DecisionButton
            label="Split off the ticked items"
            disabled={splitOff.length === 0 || splitOff.length === c.members.length}
            onDecide={(r) =>
              decide('SPLIT_CLUSTER', c.id, r, {
                groups: [c.members.map((m) => m.finding_id).filter((x) => !splitOff.includes(x)), splitOff],
              }).then((ok) => {
                if (ok) setSplitOff([]);
                return ok;
              })
            }
          />
          <DecisionButton
            label="Correct the hours"
            extra={
              <div className="flex gap-2">
                <Input label="From (h/yr)" value={min} onChange={(ev) => setMin(ev.target.value)} />
                <Input label="To (h/yr)" value={max} onChange={(ev) => setMax(ev.target.value)} />
              </div>
            }
            onDecide={(r) => decide('OVERRIDE_EFFORT', c.id, r, { min, max })}
          />
          <DecisionButton label="Not the same work" variant="danger" onDecide={(r) => decide('REJECT_CLUSTER', c.id, r)} />
        </div>
      </div>
    </Card>
  );
}

function Leadership({ data, decide }: { data: Payload; decide: Decide }) {
  return (
    <div className="space-y-4">
      <p className="m-0 text-sm text-muted-foreground">
        Leadership's views are reported, not verified. Each is set against what staff described. Management importance is what they said mattered; it
        is never the platform's priority.
      </p>
      {data.validations.map((v) => (
        <ValidationCard key={v.id} validation={v} decide={decide} />
      ))}
      {data.strategic_findings_without_verdict.length > 0 && (
        <Card title="No verdict yet">
          <ul className="m-0 list-disc space-y-1 pl-5 text-sm text-muted-foreground">
            {data.strategic_findings_without_verdict.map((s) => (
              <li key={s.id}>{s.statement}</li>
            ))}
          </ul>
        </Card>
      )}
      {data.validations.length === 0 && data.strategic_findings_without_verdict.length === 0 && (
        <Card>
          <p className="m-0 text-sm text-muted-foreground">No leadership findings yet.</p>
        </Card>
      )}
    </div>
  );
}

function ValidationCard({ validation: v, decide }: { validation: SynthesisValidation; decide: Decide }) {
  const [verdict, setVerdict] = useState<string>(v.relationship);
  const [question, setQuestion] = useState('');
  const tone = VERDICT[v.relationship];
  return (
    <Card
      title={v.strategic_finding.statement}
      action={
        <div className="flex flex-wrap items-center gap-2">
          <Badge variant={tone.variant}>{tone.label}</Badge>
          {v.material && <Badge variant="warning">Material</Badge>}
          {v.status !== 'PROPOSED' && <Badge variant="success">{humanise(v.status)}</Badge>}
        </div>
      }
    >
      <div className="space-y-3 text-sm" data-testid="validation-card">
        <p className="m-0 text-muted-foreground">
          {humanise(v.strategic_finding.persona) || 'Leadership'} · management importance {humanise(v.strategic_finding.management_importance) || 'not given'}
        </p>
        {v.what_evidence_shows && <p className="m-0">What staff describe: {v.what_evidence_shows}</p>}
        {v.note && <p className="m-0 text-muted-foreground">{v.note}</p>}
        {v.resolution && <p className="m-0">Your conclusion: {v.resolution}</p>}
        <div className="flex flex-wrap gap-2">
          {v.status === 'PROPOSED' && <DecisionButton label="Agree" variant="primary" onDecide={(r) => decide('APPROVE_VALIDATION', v.id, r)} />}
          <DecisionButton
            label="Resolve"
            extra={
              <Select
                label="Verdict"
                value={verdict}
                onChange={(e) => setVerdict(e.target.value)}
                options={Object.entries(VERDICT).map(([value, x]) => ({ value, label: x.label }))}
              />
            }
            onDecide={(r) => decide('RESOLVE_VALIDATION', v.id, r, { relationship: verdict, resolution: r })}
          />
          <DecisionButton
            label="Ask about it"
            extra={<Input label="What to ask" value={question} onChange={(e) => setQuestion(e.target.value)} />}
            onDecide={(r) => decide('REQUEST_CLARIFICATION', v.id, r, { question })}
          />
        </div>
      </div>
    </Card>
  );
}

function Opportunities({ data, decide }: { data: Payload; decide: Decide }) {
  const [adding, setAdding] = useState({ title: '', problem_statement: '', level: 'DEPARTMENT', category: 'PROCESS' });
  return (
    <div className="space-y-4">
      {data.root_causes.length > 0 && (
        <Card title="Root causes">
          <div className="space-y-3">
            {data.root_causes.map((rc) => (
              <RootCauseRow key={rc.id} rootCause={rc} decide={decide} />
            ))}
          </div>
        </Card>
      )}
      {data.opportunities.map((o) => (
        <OpportunityCard key={o.id} opportunity={o} decide={decide} />
      ))}
      <Card title="Add an opportunity">
        <DecisionButton
          label="Add"
          extra={
            <div className="grid gap-2 sm:grid-cols-2">
              <Input label="Title" value={adding.title} onChange={(e) => setAdding({ ...adding, title: e.target.value })} />
              <Select label="Level" value={adding.level} onChange={(e) => setAdding({ ...adding, level: e.target.value })} options={LEVELS.map((x) => ({ value: x, label: humanise(x) }))} />
              <Select label="Category" value={adding.category} onChange={(e) => setAdding({ ...adding, category: e.target.value })} options={CATEGORIES.map((x) => ({ value: x, label: humanise(x) }))} />
              <Textarea label="What is happening and why it matters" value={adding.problem_statement} onChange={(e) => setAdding({ ...adding, problem_statement: e.target.value })} />
            </div>
          }
          onDecide={(r) => decide('ADD_OPPORTUNITY', undefined, r, adding)}
        />
      </Card>
    </div>
  );
}

function RootCauseRow({ rootCause: rc, decide }: { rootCause: SynthesisRootCause; decide: Decide }) {
  return (
    <div className="space-y-1 text-sm">
      <p className="m-0 font-medium">{rc.statement}</p>
      <p className="m-0 text-muted-foreground">
        {rc.fact_status === 'INFERRED' ? 'Inferred' : 'Confirmed'} · {humanise(rc.confidence)} confidence
        {rc.what_would_confirm ? ` · To confirm: ${rc.what_would_confirm}` : ''}
      </p>
      {rc.status === 'PROPOSED' && (
        <div className="flex flex-wrap gap-2">
          <DecisionButton label="Confirm" onDecide={(r) => decide('APPROVE_ROOT_CAUSE', rc.id, r)} />
          <DecisionButton label="Reject" variant="danger" onDecide={(r) => decide('REJECT_ROOT_CAUSE', rc.id, r)} />
        </div>
      )}
    </div>
  );
}

function OpportunityCard({ opportunity: o, decide }: { opportunity: SynthesisOpportunity; decide: Decide }) {
  const [level, setLevel] = useState(o.level);
  const [next, setNext] = useState(o.recommended_next_action);
  return (
    <Card
      title={o.title}
      action={
        <div className="flex flex-wrap items-center gap-2">
          <Badge variant="neutral">{humanise(o.level)}</Badge>
          <Badge variant="neutral">{humanise(o.category)}</Badge>
          <Badge variant={o.status === 'APPROVED' ? 'success' : o.status === 'PROPOSED' ? 'info' : 'neutral'}>{humanise(o.status)}</Badge>
        </div>
      }
    >
      <div className="space-y-3 text-sm" data-testid="opportunity-card">
        <p className="m-0">{o.problem_statement}</p>
        {o.intervention_direction && <p className="m-0">Direction: {o.intervention_direction}</p>}
        <div className="grid gap-2 sm:grid-cols-3">
          <div>
            <p className="m-0 text-muted-foreground">Management importance</p>
            <p className="m-0 font-medium">{humanise(o.management_importance) || 'Not raised'}</p>
          </div>
          <div>
            <p className="m-0 text-muted-foreground">Platform priority</p>
            <p className="m-0 font-medium">{humanise(o.platform_priority) || '—'}</p>
          </div>
          <div>
            <p className="m-0 text-muted-foreground">Next step</p>
            <p className="m-0 font-medium">{humanise(o.recommended_next_action)}</p>
          </div>
        </div>
        {o.capacity_reference && <p className="m-0 text-muted-foreground">Capacity: {o.capacity_reference}</p>}
        {o.priority_reason && <p className="m-0 text-muted-foreground">{o.priority_reason}</p>}
        {o.planned_initiative_conflict && <p className="m-0 rounded-md bg-status-warningBg px-3 py-2">Planned change: {o.planned_initiative_conflict}</p>}
        {o.ai_note && <p className="m-0 text-muted-foreground">AI, unverified: {o.ai_note}</p>}
        <div className="flex flex-wrap gap-2">
          {o.status !== 'APPROVED' && (
            <DecisionButton label="Approve" variant="primary" onDecide={(r) => decide('APPROVE_OPPORTUNITY', o.id, r)} />
          )}
          <DecisionButton
            label="Reclassify"
            extra={
              <div className="grid gap-2 sm:grid-cols-2">
                <Select label="Level" value={level} onChange={(e) => setLevel(e.target.value)} options={LEVELS.map((x) => ({ value: x, label: humanise(x) }))} />
                <Select label="Next step" value={next} onChange={(e) => setNext(e.target.value)} options={NEXT_ACTIONS.map((x) => ({ value: x, label: humanise(x) }))} />
              </div>
            }
            onDecide={(r) => decide('RECLASSIFY_OPPORTUNITY', o.id, r, { level, recommended_next_action: next })}
          />
          {o.status !== 'DEFERRED' && <DecisionButton label="Defer" onDecide={(r) => decide('DEFER', o.id, r)} />}
          {o.status !== 'REJECTED' && <DecisionButton label="Reject" variant="danger" onDecide={(r) => decide('REJECT_OPPORTUNITY', o.id, r)} />}
        </div>
      </div>
    </Card>
  );
}

function Picture({ data, decide }: { data: Payload; decide: Decide }) {
  const picture = data.operating_picture;
  const shown: OperatingPicture = picture?.consultant ?? picture?.proposed ?? {};
  const [text, setText] = useState(shown.how_the_business_runs ?? '');
  const run = data.run;
  if (!run || !picture || !shown.how_the_business_runs) {
    return (
      <Card>
        <p className="m-0 text-sm text-muted-foreground">No operating picture yet.</p>
      </Card>
    );
  }
  return (
    <Card
      title="How the business runs today"
      action={<Badge variant={picture.status === 'APPROVED' ? 'success' : 'info'}>{picture.status === 'APPROVED' ? 'Approved' : 'Proposed'}</Badge>}
    >
      <div className="space-y-3 text-sm" data-testid="operating-picture">
        <p className="m-0 text-muted-foreground">Descriptive only — no criticism, no recommendations. It goes to the report once approved.</p>
        <p className="m-0">{shown.how_the_business_runs}</p>
        {(shown.departments ?? []).length > 0 && (
          <ul className="m-0 list-disc space-y-1 pl-5">
            {(shown.departments ?? []).map((d) => (
              <li key={d.name}>
                <strong>{d.name}</strong>
                {d.what_it_does ? ` — ${d.what_it_does}` : ''}
              </li>
            ))}
          </ul>
        )}
        <div className="flex flex-wrap gap-2">
          {picture.status !== 'APPROVED' && (
            <DecisionButton label="Approve" variant="primary" onDecide={(r) => decide('APPROVE_OPERATING_PICTURE', run.id, r)} />
          )}
          <DecisionButton
            label="Edit"
            extra={<Textarea label="How the business runs" value={text} onChange={(e) => setText(e.target.value)} />}
            onDecide={(r) => decide('EDIT_OPERATING_PICTURE', run.id, r, { operating_picture: { ...shown, how_the_business_runs: text } })}
          />
        </div>
        {picture.status === 'APPROVED' && (
          <p className="m-0 flex items-center gap-1 text-muted-foreground">
            <Check className="h-4 w-4" /> Carried into later runs as you approved it.
          </p>
        )}
      </div>
    </Card>
  );
}
