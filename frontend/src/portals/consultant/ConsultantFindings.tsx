import { useCallback, useEffect, useMemo, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { Check, EyeOff, GitMerge, Pencil, RotateCcw, UserRound } from 'lucide-react';
import {
  api,
  type Finding,
  type FindingUpdate,
  type FindingsSummary,
} from '../../lib/api';
import { useConsultantToken } from '../../lib/auth';
import {
  Badge,
  Button,
  Card,
  EmptyState,
  ErrorNotice,
  PageHeader,
  Select,
  Skeleton,
  StatCard,
  Textarea,
} from '../../components/ui';

type Filter = 'all' | 'review' | 'approved' | 'set_aside';

const FILTERS: { value: Filter; label: string }[] = [
  { value: 'all', label: 'All findings' },
  { value: 'review', label: 'Not yet reviewed' },
  { value: 'approved', label: 'Approved' },
  { value: 'set_aside', label: 'Hidden or merged' },
];

const UNIT_WORDS: Record<string, string> = {
  per_day: 'a day',
  per_week: 'a week',
  per_month: 'a month',
  per_quarter: 'a quarter',
  per_year: 'a year',
  per_event: 'each time',
};

function hoursLabel(f: Finding) {
  if (!f.annual_hours) return null;
  const { min, max } = f.annual_hours;
  return min === max ? `${min} h a year` : `${min}–${max} h a year`;
}

function frequencyLabel(f: Finding) {
  const { as_said, min, max, unit } = f.frequency;
  if (as_said) return as_said;
  if (min == null || !unit) return null;
  return `${min === max || max == null ? min : `${min}–${max}`} ${UNIT_WORDS[unit] ?? unit}`;
}

function durationLabel(f: Finding) {
  const { as_said, min, max, unit } = f.duration;
  if (as_said) return as_said;
  if (min == null || !unit) return null;
  return `${min === max || max == null ? min : `${min}–${max}`} ${unit}`;
}

/** "hr" → "HR", "finance" → "Finance"; anything already cased is left alone. */
function departmentLabel(value: string) {
  if (value !== value.toLowerCase()) return value;
  return value.length <= 3 ? value.toUpperCase() : value.charAt(0).toUpperCase() + value.slice(1);
}

function matches(f: Finding, filter: Filter) {
  if (filter === 'review') return f.status === 'draft';
  if (filter === 'approved') return f.status === 'approved';
  if (filter === 'set_aside') return f.status === 'hidden' || f.status === 'merged';
  return true;
}

/**
 * Consultant review of role-by-role findings. The page exists for two decisions a
 * generator cannot make: whether a finding is right enough to reach a client, and
 * whether two findings are the same work described by two people — in which case
 * one is merged into the other so its hours are counted once.
 */
export function ConsultantFindings() {
  const { companyId } = useParams();
  const token = useConsultantToken();
  const [findings, setFindings] = useState<Finding[]>([]);
  const [summary, setSummary] = useState<FindingsSummary | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [filter, setFilter] = useState<Filter>('all');
  const [busyId, setBusyId] = useState<number | null>(null);

  const load = useCallback(() => {
    if (!token || !companyId) return;
    api
      .consultantFindings(token, Number(companyId))
      .then((d) => {
        setFindings(d.findings);
        setSummary(d.summary);
        setError('');
      })
      .catch((err) => setError(err instanceof Error ? err.message : 'Could not load findings'))
      .finally(() => setLoading(false));
  }, [token, companyId]);

  useEffect(() => {
    load();
  }, [load]);

  const act = async (id: number, run: () => Promise<unknown>) => {
    setBusyId(id);
    try {
      await run();
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'That change did not save');
    } finally {
      setBusyId(null);
    }
  };

  const update = (id: number, payload: FindingUpdate) =>
    act(id, () => api.updateConsultantFinding(token!, Number(companyId), id, payload));
  const merge = (id: number, intoId: number) =>
    act(id, () => api.mergeConsultantFinding(token!, Number(companyId), id, intoId));

  const byId = useMemo(() => new Map(findings.map((f) => [f.id, f])), [findings]);

  // Department, then role — the report's own order.
  const groups = useMemo(() => {
    const visible = findings.filter((f) => matches(f, filter));
    const departments = new Map<string, Map<string, Finding[]>>();
    for (const f of visible) {
      const dept = f.department || 'Department not recorded';
      const role = f.role_title || 'Role not recorded';
      if (!departments.has(dept)) departments.set(dept, new Map());
      const roles = departments.get(dept)!;
      if (!roles.has(role)) roles.set(role, []);
      roles.get(role)!.push(f);
    }
    return [...departments.entries()];
  }, [findings, filter]);

  if (loading) {
    return (
      <div className="space-y-4">
        <Skeleton variant="text" />
        <Skeleton variant="card" />
      </div>
    );
  }

  const hoursValue =
    summary && summary.quantified_count > 0
      ? summary.annual_hours_min === summary.annual_hours_max
        ? `${summary.annual_hours_min}`
        : `${summary.annual_hours_min}–${summary.annual_hours_max}`
      : '—';

  return (
    <div className="space-y-6">
      <PageHeader
        title="Findings"
        description="Role by role: what the interviews found, and what it costs in time. Approve what should reach the report, and merge findings that describe the same work so it is counted once."
        breadcrumbs={[
          { label: 'Dashboard', href: '/consultant/dashboard' },
          { label: 'Company', href: `/consultant/companies/${companyId}` },
          { label: 'Findings' },
        ]}
      />

      {error && <ErrorNotice message={error} onRetry={load} />}

      {summary && (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <StatCard
            label="Hours a year"
            value={hoursValue}
            suffix={summary.quantified_count > 0 ? `from ${summary.quantified_count} costed` : undefined}
          />
          <StatCard label="Findings" value={summary.live_count} suffix={`${summary.approved_count} approved`} />
          <StatCard label="Need your review" value={summary.needs_review_count} suffix="only person in the role" />
          <StatCard label="Merged or hidden" value={summary.merged_count + summary.hidden_count} />
        </div>
      )}

      {findings.length === 0 ? (
        <EmptyState
          title="No findings yet"
          description="Findings appear as interviews finish — one for each part of someone's work where they described what snags."
        />
      ) : (
        <>
          <div className="max-w-xs">
            <Select
              label="Show"
              value={filter}
              onChange={(e) => setFilter(e.target.value as Filter)}
              options={FILTERS}
            />
          </div>

          {groups.length === 0 && (
            <p className="text-sm text-muted-foreground">Nothing matches this filter.</p>
          )}

          {groups.map(([department, roles]) => (
            <section key={department} className="space-y-4">
              <h2 className="text-section-title m-0">{departmentLabel(department)}</h2>
              {[...roles.entries()].map(([role, items]) => (
                <Card
                  key={role}
                  title={role}
                  action={
                    items.some((f) => f.single_occupant_role) ? (
                      <Badge variant="warning">Only person in this role</Badge>
                    ) : undefined
                  }
                >
                  <div className="divide-y divide-border">
                    {items.map((f) => (
                      <FindingRow
                        key={f.id}
                        finding={f}
                        mergeTargets={findings.filter(
                          (t) => t.id !== f.id && t.status !== 'merged' && t.status !== 'hidden'
                        )}
                        mergedInto={f.merged_into_id ? byId.get(f.merged_into_id) : undefined}
                        busy={busyId === f.id}
                        companyId={companyId!}
                        onUpdate={(payload) => update(f.id, payload)}
                        onMerge={(intoId) => merge(f.id, intoId)}
                      />
                    ))}
                  </div>
                </Card>
              ))}
            </section>
          ))}

          <p className="m-0 text-xs text-muted-foreground">
            Hours are worked out from what people said, on 48 working weeks, 240 working days and
            8-hour days a year. Waiting time is never counted, and hidden or merged findings are
            left out of the total.
          </p>
        </>
      )}
    </div>
  );
}

function FindingRow({
  finding: f,
  mergeTargets,
  mergedInto,
  busy,
  companyId,
  onUpdate,
  onMerge,
}: {
  finding: Finding;
  mergeTargets: Finding[];
  mergedInto?: Finding;
  busy: boolean;
  companyId: string;
  onUpdate: (payload: FindingUpdate) => void;
  onMerge: (intoId: number) => void;
}) {
  const [editing, setEditing] = useState(false);
  const [merging, setMerging] = useState(false);
  const [friction, setFriction] = useState(f.consultant.friction ?? f.original.friction ?? '');
  const [how, setHow] = useState(f.consultant.what_happens_now ?? f.original.what_happens_now ?? '');
  const [note, setNote] = useState(f.consultant.note ?? '');
  const [target, setTarget] = useState('');

  const hours = hoursLabel(f);
  const often = frequencyLabel(f);
  const long = durationLabel(f);
  const setAside = f.status === 'hidden' || f.status === 'merged';

  const save = () => {
    onUpdate({
      // Sending the interview's own words back unchanged would read as an edit.
      consultant_friction: friction.trim() === (f.original.friction ?? '').trim() ? '' : friction.trim(),
      consultant_what_happens_now: how.trim() === (f.original.what_happens_now ?? '').trim() ? '' : how.trim(),
      consultant_note: note.trim(),
    });
    setEditing(false);
  };

  return (
    <article className={`space-y-3 py-4 first:pt-0 last:pb-0 ${setAside ? 'opacity-60' : ''}`}>
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0 space-y-1">
          <h3 className="m-0 text-base font-semibold capitalize text-foreground">{f.title}</h3>
          <p className="m-0 text-sm text-foreground">{f.friction}</p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          {hours ? (
            <Badge variant="info">{hours}</Badge>
          ) : (
            <Badge variant="neutral">Not quantified</Badge>
          )}
          {f.status === 'approved' && <Badge variant="success">Approved</Badge>}
          {f.status === 'hidden' && <Badge variant="neutral">Hidden</Badge>}
          {f.status === 'merged' && <Badge variant="neutral">Merged</Badge>}
          {f.needs_review && <Badge variant="warning">Review before release</Badge>}
        </div>
      </div>

      {f.what_happens_now && (
        <p className="m-0 text-sm text-muted-foreground">
          <span className="font-medium text-foreground">What happens now: </span>
          {f.what_happens_now}
        </p>
      )}

      <dl className="m-0 grid gap-x-6 gap-y-1 text-sm sm:grid-cols-3">
        <div>
          <dt className="text-xs text-muted-foreground">How often</dt>
          <dd className="m-0">{often ?? 'Not said'}</dd>
        </div>
        <div>
          <dt className="text-xs text-muted-foreground">How long</dt>
          <dd className="m-0">{long ?? 'Not said'}</dd>
        </div>
        <div>
          <dt className="text-xs text-muted-foreground">Basis</dt>
          <dd className="m-0">
            {f.basis === 'discovery_partial' ? 'Unfinished interview' : 'Interview'} · {f.confidence} confidence
          </dd>
        </div>
      </dl>

      {f.effort_type === 'waiting' ? (
        <p className="m-0 text-xs text-muted-foreground">
          This is time spent waiting, so it adds no hours.
        </p>
      ) : (
        !hours &&
        typeof f.hours_basis.reason === 'string' && (
          <p className="m-0 text-xs text-muted-foreground">
            No hours: {f.hours_basis.reason}.
          </p>
        )
      )}
      {f.consultant.note && !editing && (
        <p className="m-0 text-sm text-muted-foreground">
          <span className="font-medium text-foreground">Your note: </span>
          {f.consultant.note}
        </p>
      )}
      {mergedInto && (
        <p className="m-0 text-sm text-muted-foreground">
          Merged into “{mergedInto.title}”{mergedInto.role_title ? ` (${mergedInto.role_title})` : ''} — its hours
          are counted there.
        </p>
      )}

      {editing && (
        <div className="space-y-3 rounded-md border border-border p-3">
          <Textarea label="What snags" value={friction} onChange={(e) => setFriction(e.target.value)} />
          <Textarea label="What happens now" value={how} onChange={(e) => setHow(e.target.value)} />
          <Textarea
            label="Note for yourself and co-consultants"
            value={note}
            onChange={(e) => setNote(e.target.value)}
          />
          <p className="m-0 text-xs text-muted-foreground">
            Describe the work and the systems, never the person. The interview's own words are kept either way.
          </p>
          <div className="flex gap-2">
            <Button size="sm" onClick={save} loading={busy}>
              Save wording
            </Button>
            <Button size="sm" variant="secondary" onClick={() => setEditing(false)}>
              Cancel
            </Button>
          </div>
        </div>
      )}

      {merging && (
        <div className="flex flex-wrap items-end gap-2 rounded-md border border-border p-3">
          <div className="min-w-[16rem] flex-1">
            <Select
              label="The same work as"
              value={target}
              onChange={(e) => setTarget(e.target.value)}
              options={[
                { value: '', label: 'Choose a finding…' },
                ...mergeTargets.map((t) => ({
                  value: String(t.id),
                  label: `${t.title} — ${t.role_title ?? 'role not recorded'}${t.employee?.name ? `, ${t.employee.name}` : ''}`,
                })),
              ]}
            />
          </div>
          <Button
            size="sm"
            disabled={!target}
            loading={busy}
            onClick={() => {
              onMerge(Number(target));
              setMerging(false);
            }}
          >
            Merge
          </Button>
          <Button size="sm" variant="secondary" onClick={() => setMerging(false)}>
            Cancel
          </Button>
        </div>
      )}

      {!editing && !merging && (
        <div className="flex flex-wrap items-center gap-2">
          {setAside ? (
            <Button
              size="sm"
              variant="secondary"
              icon={<RotateCcw className="h-4 w-4" />}
              loading={busy}
              onClick={() => onUpdate({ status: 'draft' })}
            >
              {f.status === 'merged' ? 'Undo merge' : 'Restore'}
            </Button>
          ) : (
            <>
              {f.status !== 'approved' && (
                <Button size="sm" icon={<Check className="h-4 w-4" />} loading={busy} onClick={() => onUpdate({ status: 'approved' })}>
                  Approve
                </Button>
              )}
              <Button size="sm" variant="secondary" icon={<Pencil className="h-4 w-4" />} onClick={() => setEditing(true)}>
                Edit wording
              </Button>
              {mergeTargets.length > 0 && (
                <Button size="sm" variant="secondary" icon={<GitMerge className="h-4 w-4" />} onClick={() => setMerging(true)}>
                  Same work as…
                </Button>
              )}
              <Button
                size="sm"
                variant="secondary"
                icon={<EyeOff className="h-4 w-4" />}
                loading={busy}
                onClick={() => onUpdate({ status: 'hidden' })}
              >
                Hide
              </Button>
            </>
          )}
          {f.conversation_id && (
            <Link
              to={`/consultant/companies/${companyId}/conversations/${f.conversation_id}`}
              className="ml-auto inline-flex items-center gap-1 text-sm text-accent hover:underline"
            >
              <UserRound className="h-4 w-4" />
              {f.employee?.name ? `${f.employee.name}'s interview` : 'Interview'}
            </Link>
          )}
        </div>
      )}
    </article>
  );
}
