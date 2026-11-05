import { useCallback, useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { ArrowLeft, Lock } from 'lucide-react';
import {
  api,
  type ConsultantLeadership as Payload,
  type ConsultantLeadershipContext,
  type ConsultantLeadershipFinding,
  type ConsultantLeadershipParticipant,
} from '../../lib/api';
import { useConsultantToken } from '../../lib/auth';
import { Badge, Button, Card, Input, PageHeader, Select, Textarea } from '../../components/ui';
import { cn } from '../../lib/cn';

const COVERAGE_TONE: Record<string, string> = {
  USABLE: 'bg-status-successBg text-status-success',
  PARTIAL: 'bg-status-warningBg text-foreground',
  UNKNOWN: 'bg-muted text-muted-foreground line-through',
  OPEN: 'bg-muted/40 text-muted-foreground',
};

const FIELD_LABELS: Record<string, string> = {
  strategic_objectives: 'Objectives',
  growth_priorities: 'Growth',
  management_priorities: 'Priorities',
  concerns: 'Concerns',
  operational_bottlenecks: 'Bottlenecks',
  stakeholder_friction: 'Stakeholder friction',
  people_and_capacity: 'People and capacity',
  systems_view: 'Systems',
  reporting_gaps: 'Reporting',
  decision_structure: 'Decisions and approvals',
  data_document_concerns: 'Data and documents',
  constraints: 'Constraints',
  ambition_and_missed_capability: 'Ambition',
  released_time_preferences: 'Where released time should go',
  priority_areas: 'Where to look first',
};

const humanise = (s: string | null | undefined) => (s ?? '').toLowerCase().replace(/_/g, ' ');

/**
 * The conversations with leadership for one company (Doc 08): who is taking
 * part, coverage, what each produced, and the consultant-only notes. Consultants
 * only — none of this reaches the client or employees.
 */
export function ConsultantLeadership() {
  const { companyId = '' } = useParams();
  const id = Number(companyId);
  const token = useConsultantToken();
  const [data, setData] = useState<Payload | null>(null);
  const [error, setError] = useState('');

  useEffect(() => {
    if (!token) return;
    api.consultantLeadership(token, id).then(setData).catch((e) => setError(e instanceof Error ? e.message : 'Failed to load'));
  }, [token, id]);

  const act = useCallback(
    async (path: string, method: 'POST' | 'PATCH', body?: Record<string, unknown>) => {
      if (!token) return;
      setError('');
      try {
        setData(await api.consultantLeadershipAction(token, id, path, method, body));
      } catch (e) {
        setError(e instanceof Error ? e.message : 'That did not work');
      }
    },
    [token, id]
  );

  return (
    <div className="space-y-6">
      <Link to={`/consultant/companies/${companyId}`} className="inline-flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground">
        <ArrowLeft className="h-4 w-4" /> Company overview
      </Link>
      <PageHeader
        title="Leadership conversations"
        description="One person's view each, kept separate. Management views are reported, not verified."
      />
      {error && <p className="m-0 rounded-md bg-destructive/10 px-3 py-2 text-sm text-destructive">{error}</p>}
      {!data ? (
        <p className="text-sm text-muted-foreground">Loading…</p>
      ) : (
        <>
          {!data.available && (
            <p className="m-0 rounded-md bg-status-warningBg px-3 py-2 text-sm">
              The conversation isn't switched on here (AI_KEY_PERSON or no model), so clients are told the team will
              arrange it.
            </p>
          )}
          <PlanCard data={data} onSave={(departments) => act('plan', 'PATCH', { departments })} />
          {data.participants.length === 0 && (
            <Card>
              <p className="m-0 text-sm text-muted-foreground">Nobody yet — the conversations begin once onboarding is submitted.</p>
            </Card>
          )}
          {data.participants.map((p) => (
            <ParticipantCard key={p.id} participant={p} data={data} act={act} />
          ))}
        </>
      )}
    </div>
  );
}

function PlanCard({ data, onSave }: { data: Payload; onSave: (rows: { name: string; count: string }[]) => void }) {
  const [rows, setRows] = useState(
    data.engagement.planned_departments.map((d) => ({ name: d.name, count: d.count === 'UNKNOWN' ? '' : String(d.count) }))
  );
  return (
    <Card title="Who takes part">
      <div className="space-y-2">
        <p className="m-0 text-sm text-muted-foreground">
          {data.engagement.planned_participant_count == null
            ? 'Some counts are still unknown; pricing waits for them.'
            : `${data.engagement.planned_participant_count} people planned.`}
        </p>
        {rows.map((r, i) => (
          <div key={i} className="flex gap-2">
            <span className="min-w-0 flex-1 self-center text-sm">{r.name}</span>
            <div className="w-28">
              <Input
                aria-label={`People from ${r.name}`}
                value={r.count}
                placeholder="Unknown"
                disabled={!data.engagement.plan_editable}
                onChange={(e) => setRows((prev) => prev.map((x, j) => (j === i ? { ...x, count: e.target.value } : x)))}
              />
            </div>
          </div>
        ))}
        {data.engagement.plan_editable && (
          <div className="flex justify-end">
            <Button size="sm" onClick={() => onSave(rows.map((r) => ({ name: r.name, count: r.count || 'UNKNOWN' })))}>
              Save counts
            </Button>
          </div>
        )}
      </div>
    </Card>
  );
}

function ParticipantCard({
  participant: p,
  data,
  act,
}: {
  participant: ConsultantLeadershipParticipant;
  data: Payload;
  act: (path: string, method: 'POST' | 'PATCH', body?: Record<string, unknown>) => Promise<void>;
}) {
  const [persona, setPersona] = useState(p.persona ?? 'OTHER');
  const [focus, setFocus] = useState(p.consultant_focus ?? '');
  const session = p.sessions[p.sessions.length - 1];
  const context = p.contexts[p.contexts.length - 1];
  const base = `participants/${p.id}`;

  return (
    <Card
      title={`${p.name}${p.key_user ? ' (key user)' : ''}`}
      action={
        <div className="flex flex-wrap items-center gap-2">
          <Badge variant={p.participation_status === 'COMPLETED' ? 'success' : 'info'}>{humanise(p.participation_status)}</Badge>
          {session?.needs_review && <Badge variant="warning">Needs review</Badge>}
        </div>
      }
    >
      <div className="space-y-5">
        <p className="m-0 text-sm text-muted-foreground">
          {[p.role_title, p.scope, p.email].filter(Boolean).join(' · ') || 'No details'}
          {p.invited_at ? ` · invited ${new Date(p.invited_at).toLocaleDateString()}` : ''}
          {p.reminder_count > 0 ? ` · ${p.reminder_count} reminder${p.reminder_count === 1 ? '' : 's'}` : ''}
        </p>

        <div className="grid gap-3 sm:grid-cols-[14rem_1fr_auto] sm:items-end">
          <Select
            label="Persona"
            value={persona}
            options={data.personas.map((x) => ({ value: x, label: humanise(x) }))}
            onChange={(e) => setPersona(e.target.value)}
          />
          <Input
            label="Neutral focus (never shown to them)"
            value={focus}
            placeholder="e.g. quotation turnaround"
            onChange={(e) => setFocus(e.target.value)}
          />
          <Button variant="secondary" onClick={() => void act(base, 'PATCH', { participant: { persona, consultant_focus: focus } })}>
            Save
          </Button>
        </div>

        <div className="flex flex-wrap gap-2">
          {p.can_invite && !['COMPLETED', 'ABANDONED'].includes(p.participation_status) && (
            <Button size="sm" variant="secondary" onClick={() => void act(`${base}/invite`, 'POST')}>Send invitation again</Button>
          )}
          {!p.can_invite && <span className="text-sm text-muted-foreground">No email address — can't invite</span>}
          {session && !['COMPLETE', 'ABANDONED'].includes(session.state) && (
            <Button size="sm" variant="ghost" onClick={() => void act(`${base}/close`, 'POST')}>Close unfinished</Button>
          )}
          {session && ['COMPLETE', 'ABANDONED'].includes(session.state) && (
            <Button size="sm" variant="ghost" onClick={() => void act(`${base}/further_session`, 'POST')}>Another session</Button>
          )}
        </div>

        {session && (
          <div className="space-y-2">
            <p className="m-0 text-sm text-foreground">
              Session {session.version}: {humanise(session.state)}
              {session.close_reason ? ` — ${humanise(session.close_reason)}` : ''} · {session.turn_count} turns
            </p>
            {session.review_reasons.length > 0 && (
              <p className="m-0 text-sm text-foreground">
                Review: {session.review_reasons.map((r) => `${humanise(r.type)}${r.turn ? ` (${r.turn})` : ''}`).join(', ')}
              </p>
            )}
            <div className="flex flex-wrap gap-1.5">
              {data.areas.map((area) => (
                <span key={area} className={cn('rounded px-2 py-0.5 text-xs', COVERAGE_TONE[session.coverage[area]] ?? COVERAGE_TONE.OPEN)}>
                  {humanise(area)}
                </span>
              ))}
            </div>
          </div>
        )}

        {context && <ContextView context={context} act={act} />}

        {session && (session.document_requests.length > 0 || session.documents.length > 0) && (
          <div className="space-y-1 text-sm">
            <p className="m-0 font-medium">Documents</p>
            {session.document_requests.map((r) => (
              <p key={r.id} className="m-0 text-muted-foreground">
                {r.requested_item} — {humanise(r.status)}
              </p>
            ))}
            {session.documents.map((d) => (
              <p key={d.id} className="m-0 text-muted-foreground">Uploaded: {d.filename}</p>
            ))}
          </div>
        )}

        {session && session.transcript.length > 0 && (
          <details className="rounded-md border border-border p-3">
            <summary className="cursor-pointer text-sm font-medium">Transcript and what was captured</summary>
            <ol className="m-0 mt-3 list-none space-y-3 p-0">
              {session.transcript.map((t) => (
                <li key={t.index} className="text-sm">
                  <span className="mr-2 font-mono text-xs text-muted-foreground">{t.locator}</span>
                  <span className="font-medium">{t.direction === 'AI' ? 'Assistant' : t.direction === 'SYSTEM' ? 'System' : p.name}</span>
                  {t.mode && (
                    <span className="ml-2 text-xs text-muted-foreground">
                      {humanise(t.mode)}
                      {t.targeted_slot ? ` · ${humanise(t.targeted_slot)}` : ''}
                      {t.fallback_reason ? ` · fallback: ${t.fallback_reason}` : ''}
                    </span>
                  )}
                  {t.slots_filled.length > 0 && (
                    <span className="ml-2 text-xs text-status-success">filled {t.slots_filled.map(humanise).join(', ')}</span>
                  )}
                  <p dir="auto" className="m-0 mt-1 whitespace-pre-wrap text-foreground">{t.text}</p>
                  {t.capture && (
                    <details className="mt-1">
                      <summary className="cursor-pointer text-xs text-muted-foreground">Capture</summary>
                      <pre className="m-0 mt-1 overflow-x-auto rounded bg-muted p-2 text-xs">{JSON.stringify(t.capture, null, 2)}</pre>
                    </details>
                  )}
                </li>
              ))}
            </ol>
          </details>
        )}
      </div>
    </Card>
  );
}

function ContextView({
  context,
  act,
}: {
  context: ConsultantLeadershipContext;
  act: (path: string, method: 'POST' | 'PATCH', body?: Record<string, unknown>) => Promise<void>;
}) {
  const content = context.content as Record<string, unknown>;
  const success = content.success_definition as { text?: string | null } | undefined;
  const appetite = content.change_appetite_inferred as { level?: string; basis?: string } | undefined;
  const politics = context.consultant_private.political_context ?? {};
  const notes = context.consultant_private.consultant_notes ?? [];

  return (
    <div className="space-y-4 border-t border-border pt-4">
      <p className="m-0 text-sm font-medium">
        What they said (version {context.version}
        {context.status === 'INCOMPLETE' ? ', built from the turn captures — check it' : ''})
      </p>
      {success?.text && <p className="m-0 text-sm"><span className="font-medium">Success would be:</span> {success.text}</p>}
      <div className="grid gap-3 sm:grid-cols-2">
        {Object.entries(FIELD_LABELS).map(([key, label]) => {
          const items = (content[key] as { text?: string; preferred_focus?: string; role_or_team?: string; evidence?: string[] }[]) ?? [];
          if (!items.length) return null;
          return (
            <div key={key} className="text-sm">
              <p className="m-0 font-medium">{label}</p>
              <ul className="m-0 pl-5 text-muted-foreground">
                {items.map((item, i) => (
                  <li key={i}>
                    {item.text ?? `${item.role_or_team}: ${item.preferred_focus}`}{' '}
                    <span className="font-mono text-xs">{(item.evidence ?? []).join(' ')}</span>
                  </li>
                ))}
              </ul>
            </div>
          );
        })}
      </div>
      {appetite?.level && (
        <p className="m-0 text-sm text-muted-foreground">
          Change appetite (inferred): {humanise(appetite.level)}{appetite.basis ? ` — ${appetite.basis}` : ''}
        </p>
      )}

      {context.findings.length > 0 && (
        <div className="space-y-2">
          <p className="m-0 text-sm font-medium">Strategic findings (reported, to be checked)</p>
          {context.findings.map((f) => (
            <FindingRow key={f.id} finding={f} act={act} />
          ))}
        </div>
      )}

      {context.initiatives.length > 0 && (
        <div className="text-sm">
          <p className="m-0 font-medium">Planned changes</p>
          <ul className="m-0 pl-5 text-muted-foreground">
            {context.initiatives.map((i) => (
              <li key={i.id}>
                {humanise(i.initiative_type)}: {i.description}
                {i.timing ? ` (${i.timing})` : ''} — {humanise(i.status)}
              </li>
            ))}
          </ul>
        </div>
      )}

      {(context.unknowns.length > 0 || context.contradictions.length > 0) && (
        <div className="grid gap-3 text-sm sm:grid-cols-2">
          {context.unknowns.length > 0 && (
            <div>
              <p className="m-0 font-medium">Still unknown</p>
              <ul className="m-0 pl-5 text-muted-foreground">
                {context.unknowns.map((u, i) => <li key={i}>{humanise(u.domain)}: {u.note}</li>)}
              </ul>
            </div>
          )}
          {context.contradictions.length > 0 && (
            <div>
              <p className="m-0 font-medium">Contradictions</p>
              <ul className="m-0 pl-5 text-muted-foreground">
                {context.contradictions.map((c, i) => <li key={i}>{c.between}: {c.note}</li>)}
              </ul>
            </div>
          )}
        </div>
      )}

      <div className="text-sm">
        <p className="m-0 font-medium">May be passed to staff interviews</p>
        {context.neutral_employee_context.length ? (
          <ul className="m-0 pl-5 text-muted-foreground">
            {context.neutral_employee_context.map((n, i) => <li key={i}>{n.department}: {n.context}</li>)}
          </ul>
        ) : (
          <p className="m-0 text-muted-foreground">Nothing.</p>
        )}
      </div>

      <div className="rounded-md border border-dashed border-border p-3 text-sm">
        <p className="m-0 mb-1 inline-flex items-center gap-1 font-medium"><Lock className="h-3.5 w-3.5" /> Consultant only</p>
        {Object.entries(politics).flatMap(([kind, list]) =>
          (list ?? []).map((item, i) => (
            <p key={`${kind}-${i}`} className="m-0 text-muted-foreground">{humanise(kind)}: {item.note}</p>
          ))
        )}
        {notes.map((n, i) => (
          <p key={`n-${i}`} className="m-0 text-muted-foreground">{humanise(n.type)}: {n.note}</p>
        ))}
        {Object.values(politics).every((l) => !l?.length) && notes.length === 0 && (
          <p className="m-0 text-muted-foreground">Nothing recorded.</p>
        )}
      </div>
    </div>
  );
}

function FindingRow({
  finding: f,
  act,
}: {
  finding: ConsultantLeadershipFinding;
  act: (path: string, method: 'POST' | 'PATCH', body?: Record<string, unknown>) => Promise<void>;
}) {
  const [editing, setEditing] = useState(false);
  const [statement, setStatement] = useState(f.statement);
  const [rationale, setRationale] = useState('');

  if (f.status === 'REJECTED') {
    return (
      <p className="m-0 text-sm text-muted-foreground line-through">
        {f.statement} <span className="no-underline">(rejected: {f.edit_rationale})</span>
      </p>
    );
  }

  return (
    <div className="rounded-md bg-muted/40 p-3 text-sm">
      {editing ? (
        <div className="space-y-2">
          <Textarea value={statement} onChange={(e) => setStatement(e.target.value)} />
          <Input placeholder="Why (required)" value={rationale} onChange={(e) => setRationale(e.target.value)} />
          <div className="flex justify-end gap-2">
            <Button size="sm" variant="ghost" onClick={() => setEditing(false)}>Cancel</Button>
            <Button size="sm" variant="ghost" disabled={!rationale.trim()}
              onClick={() => void act(`findings/${f.id}`, 'PATCH', { reject: true, rationale })}>
              Reject
            </Button>
            <Button size="sm" disabled={!rationale.trim()}
              onClick={() => void act(`findings/${f.id}`, 'PATCH', { finding: { statement }, rationale })}>
              Save correction
            </Button>
          </div>
        </div>
      ) : (
        <>
          <p className="m-0 text-foreground">{f.statement}</p>
          <p className="m-0 mt-1 text-xs text-muted-foreground">
            {humanise(f.category)} · {humanise(f.scope)} · {humanise(f.symptom_or_cause)} · importance to them:{' '}
            {humanise(f.management_importance)} · {f.evidence.join(' ')}
            {f.version > 1 ? ` · corrected: ${f.edit_rationale}` : ''}
          </p>
          {f.validation_need && <p className="m-0 mt-1 text-xs text-muted-foreground">To check: {f.validation_need}</p>}
          <Button size="sm" variant="ghost" className="mt-1" onClick={() => setEditing(true)}>Correct or reject</Button>
        </>
      )}
    </div>
  );
}
