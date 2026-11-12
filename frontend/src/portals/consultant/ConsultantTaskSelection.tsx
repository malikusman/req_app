import { useEffect, useState } from 'react';
import { Link, useParams, useSearchParams } from 'react-router-dom';
import { Button, Card } from '../../components/ui';
import { DashboardShell } from '../../components/ui/DashboardShell';
import { api } from '../../lib/api';
import { useConsultantToken } from '../../lib/auth';
import type { ReviewCommand, ReviewParticipant, ReviewTask, SelectionReview, SelectionRun, TaskSource } from '../../lib/taskSelection';
import { ProposalEvidence, RelationshipEvidence, sourceLabel, TextList, words, workload } from './TaskSelectionEvidence';

const field = 'rounded-md border border-border bg-background px-2 py-1 text-foreground';
type Save = (command: ReviewCommand) => void;

export function ConsultantTaskSelection() {
  const { companyId = '' } = useParams();
  const token = useConsultantToken();
  const [search, setSearch] = useSearchParams();
  const run = search.get('run');
  const version = search.get('version');
  const [runList, setRunList] = useState<{ company: string; runs: SelectionRun[]; before: number | null }>();
  const [review, setReview] = useState<SelectionReview>();
  const [error, setError] = useState('');
  const [reload, setReload] = useState(0);
  const [busy, setBusy] = useState(false);
  const [reason, setReason] = useState('');
  const base = `/consultant/companies/${companyId}`;

  useEffect(() => {
    if (!token) return;
    let active = true;
    api.consultantTaskIntelligenceRuns(token, companyId).then(page => {
      if (active) setRunList({ company: companyId, runs: page.task_intelligence_runs, before: page.next_before_id });
    }).catch(err => { if (active) setError(err.message); });
    return () => { active = false; };
  }, [companyId, token, reload]);

  const runs = runList?.company === companyId ? runList.runs : undefined;
  useEffect(() => {
    if (!run && runs?.length) setSearch({ run: String(runs[0].id) }, { replace: true });
  }, [run, runs, setSearch]);

  useEffect(() => {
    setReview(undefined);
    setReason('');
    if (!token || !run) return;
    let active = true;
    api.consultantTaskSelection(token, companyId, run, version)
      .then(data => { if (active) setReview(data); })
      .catch(err => { if (active) setError(err.message); });
    return () => { active = false; };
  }, [companyId, token, run, version, reload]);

  const current = review && String(review.run.id) === run && (version === null || String(review.version) === version) ? review : undefined;
  const readOnly = !current || current.status === 'finalized' || version !== null;
  async function save(command: ReviewCommand) {
    if (!token || !run || !current || readOnly || busy) return;
    if (!reason.trim()) { setError('Enter a reason for this decision.'); return; }
    setBusy(true);
    setError('');
    try {
      setReview(await api.consultantTaskSelectionCommand(token, companyId, run, {
        ...command, expected_version: current.version, reason: reason.trim(),
      }));
      setReason('');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not save the decision.');
    } finally {
      setBusy(false);
    }
  }

  async function loadOlderRuns() {
    if (!token || !runList?.before) return;
    try {
      const page = await api.consultantTaskIntelligenceRuns(token, companyId, runList.before);
      setRunList(previous => previous?.company === companyId
        ? { ...previous, runs: [...previous.runs, ...page.task_intelligence_runs.filter(item => !previous.runs.some(row => row.id === item.id))], before: page.next_before_id }
        : previous);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not load older runs.');
    }
  }

  return <DashboardShell title="Task selection" description="Review recommended processes and approve the tasks to take into Deep Dive planning.">
    <div className="flex flex-wrap items-center gap-4 text-sm">
      <Link className="text-primary underline" to={base}>Company overview</Link>
      {run && <label>Task Intelligence run <select className={field} value={run} disabled={busy} onChange={event => {
        setError(''); setSearch({ run: event.target.value });
      }}>
        {!runs?.some(item => String(item.id) === run) && <option value={run}>Run #{run}</option>}
        {runs?.map(item => <option key={item.id} value={item.id}>Version {item.version} · run #{item.id}</option>)}
      </select></label>}
      {!!runList?.before && <Button variant="secondary" size="sm" onClick={loadOlderRuns}>Load older runs</Button>}
      {current && <label>Review revision <select className={field} value={version ?? ''} disabled={busy} onChange={event => {
        setError(''); setSearch(event.target.value ? { run: run!, version: event.target.value } : { run: run! });
      }}>
        <option value="">Latest (v{current.latest_version})</option><option value="0">Initial proposals</option>
        {current.history.map(item => <option key={item.version} value={item.version}>v{item.version} · {item.action}</option>)}
      </select></label>}
      <Button size="sm" variant="secondary" disabled={busy} onClick={() => { setError(''); setReload(value => value + 1); }}>Reload review</Button>
    </div>
    {error && <p role="alert" className="rounded-md border border-warning p-3 text-sm">{error}</p>}
    {runs && !runs.length && !run && <Card title="No Task Intelligence runs"><p>Run Task Intelligence for this company to start a review.</p></Card>}
    {!current && !error && (!runs || runs.length > 0 || run) && <p role="status">Loading task selection…</p>}
    {current && <ReviewContent key={`${current.run.id}:${current.version}:${version ?? 'latest'}`}
      review={current} readOnly={readOnly} busy={busy} reason={reason} setReason={setReason} save={save} />}
  </DashboardShell>;
}

function ReviewContent({ review, readOnly, busy, reason, setReason, save }: {
  review: SelectionReview; readOnly: boolean; busy: boolean; reason: string; setReason: (value: string) => void; save: Save;
}) {
  const { snapshot, sources, eligible_participants: people } = review;
  const [merge, setMerge] = useState<string[]>([]);
  const live = snapshot.tasks.filter(task => !['merged', 'split'].includes(task.status));
  const selected = snapshot.selected_order.flatMap(id => live.filter(task => task.id === id));
  const replaced = snapshot.tasks.filter(task => !live.includes(task));
  const viewStatus = snapshot.final_selection ? (snapshot.final_selection.provisional ? 'Finalized with unresolved gaps' : 'Finalized') : 'Draft';

  function move(index: number, offset: number) {
    const task_ids = [...snapshot.selected_order];
    [task_ids[index], task_ids[index + offset]] = [task_ids[index + offset], task_ids[index]];
    save({ action: 'reorder', task_ids });
  }

  return <div className="space-y-6">
    <Card title="Selected tasks">
      <div className="space-y-3 text-sm">
        <p role="status">{viewStatus} · review v{review.version} · run v{review.run.version}{readOnly && review.status === 'draft' ? ' · read-only revision' : ''}</p>
        <p>{snapshot.sampling.planned_interviews} planned interviews · {snapshot.sampling.available_slots ?? 'unknown'} available slots</p>
        <TextList items={snapshot.sampling.gaps} />
        {!readOnly && <label className="block">Reason for next decision
          <textarea className={`${field} ml-2 align-middle`} rows={2} maxLength={2000} value={reason} onChange={event => setReason(event.target.value)} />
        </label>}
        {selected.length ? <ol className="list-decimal space-y-2 pl-5">{selected.map((task, index) => <li key={task.id}>
          {task.title}{task.gaps.length ? ' · provisional' : ''}
          {!readOnly && <span className="ml-2 inline-flex gap-2">
            <Button variant="secondary" size="sm" disabled={busy || index === 0} onClick={() => move(index, -1)} aria-label={`Move ${task.title} up`}>Up</Button>
            <Button variant="secondary" size="sm" disabled={busy || index === selected.length - 1} onClick={() => move(index, 1)} aria-label={`Move ${task.title} down`}>Down</Button>
          </span>}
        </li>)}</ol> : <p>No tasks selected.</p>}
        {!readOnly && <fieldset disabled={busy} className="flex flex-wrap items-end gap-3">
          <form className="flex flex-wrap items-end gap-2" onSubmit={event => {
            event.preventDefault();
            const value = new FormData(event.currentTarget).get('slots');
            save({ action: 'capacity', slots: value === '' ? null : Number(value) });
          }}>
            <label>Available interview slots <input className={`${field} w-24`} name="slots" type="number" min="0" max="1000" defaultValue={snapshot.sampling.available_slots ?? ''} /></label>
            <Button variant="secondary" size="sm" type="submit">Save capacity</Button>
          </form>
          <Button disabled={!selected.length || busy} onClick={() => save({ action: 'finalize' })}>Finalize selection</Button>
        </fieldset>}
        {!readOnly && <p className="text-muted-foreground">Finalizing locks this review. Unresolved gaps stay attached to the selected tasks.</p>}
      </div>
    </Card>

    <Card title="Task Intelligence proposals">
      <div className="space-y-3 text-sm">
        <p className="text-muted-foreground">Evaluation mode · {words(review.run.evaluation_mode)}. The original proposals remain available after review.</p>
        {review.proposals.map(proposal => <ProposalEvidence key={proposal.id} proposal={proposal} sources={sources} />)}
        {!review.proposals.length && <p>No proposals in this run. You can add a task manually.</p>}
      </div>
    </Card>

    <Card title="Relationships and clarifications">
      <div className="space-y-3 text-sm">
        {review.relationships.map(pair => <RelationshipEvidence key={pair.source_ids.join(':')} relationship={pair} sources={sources} />)}
        {!review.relationships.length && <p>No source relationships recorded in this run.</p>}
        {Object.values(snapshot.relationship_overrides).map(override => <p key={override.source_ids.join(':')}>
          Consultant judgment · sources {override.source_ids.join(' and ')} · {words(override.classification)}. {override.reason}
        </p>)}
        {!readOnly && sources.length > 1 && <RelationshipForm sources={sources} save={save} busy={busy} />}
      </div>
    </Card>

    <Card title="Review tasks">
      <div className="space-y-4 text-sm">
        {!readOnly && <fieldset disabled={busy} className="flex flex-wrap gap-4">
          <TaskTitleForm action="add" sources={sources} save={save} />
          <TaskTitleForm action="merge" selected={merge} save={save} />
        </fieldset>}
        {live.map(task => <TaskCard key={task.id} task={task} sources={sources.filter(item => task.source_ids.includes(item.id))}
          people={people} readOnly={readOnly} busy={busy} save={save} merged={merge.includes(task.id)} toggleMerge={() => {
            setMerge(list => list.includes(task.id) ? list.filter(id => id !== task.id) : [...list, task.id]);
          }} />)}
        {!!replaced.length && <details><summary>Replaced tasks</summary><ul className="list-disc pl-5">
          {replaced.map(task => <li key={task.id}>{task.title} · {task.status} · {task.replacement_reason}</li>)}
        </ul></details>}
      </div>
    </Card>
    <Card title="Decision history">
      <ol className="list-decimal space-y-2 pl-5 text-sm">
        {review.history.filter(item => item.version <= review.version).map(item => <li key={item.version}>
          v{item.version} · {words(item.action)} · consultant #{item.consultant_user_id} · {new Date(item.created_at).toLocaleString()} · {item.reason}
        </li>)}
      </ol>
      {!review.version && <p className="text-sm">No consultant decisions yet.</p>}
    </Card>
  </div>;
}

function SourceChecks({ sources }: { sources: TaskSource[] }) {
  return <div className="space-y-1">{sources.map(source => <label className="block" key={source.id}>
    <input type="checkbox" name="sources" value={source.id} /> {sourceLabel(source)}
  </label>)}</div>;
}

function TaskTitleForm({ action, selected = [], sources = [], save }: {
  action: 'add' | 'merge'; selected?: string[]; sources?: TaskSource[]; save: Save;
}) {
  const label = action === 'add' ? 'Add task' : 'Merge marked tasks';
  return <details><summary className="cursor-pointer font-medium">{label}{action === 'merge' ? ` (${selected.length})` : ''}</summary>
    <form className="mt-2 space-y-2" onSubmit={event => {
      event.preventDefault();
      const data = new FormData(event.currentTarget);
      save({ action, title: String(data.get('title')), source_ids: data.getAll('sources').map(Number), task_ids: selected });
    }}>
      <label>{action === 'add' ? 'New task title' : 'Merged task title'} <input className={field} name="title" required maxLength={255} /></label>
      {sources.length > 0 && <SourceChecks sources={sources} />}
      <div><Button type="submit" size="sm" disabled={action === 'merge' && selected.length < 2}>{label}</Button></div>
    </form>
  </details>;
}

function TaskCard({ task, sources, people, readOnly, busy, save, merged, toggleMerge }: {
  task: ReviewTask; sources: TaskSource[]; people: ReviewParticipant[]; readOnly: boolean;
  busy: boolean; save: Save; merged: boolean; toggleMerge: () => void;
}) {
  return <section aria-label={task.title} className="space-y-2 rounded-md border border-border p-3">
    <h3 className="font-semibold">{task.title} · {task.status}</h3>
    {task.decision_reason && <p>{task.decision_reason}</p>}
    <p>Review workload · {workload(task.effective_effort)}</p>
    <p>Participants · {task.participant_ids.map(id => `${people.find(person => person.id === id)?.name || 'Employee'} #${id}`).join(', ') || 'none'}</p>
    {task.participant_reason && <p>{task.participant_reason}</p>}
    {!!task.origin_task_ids.length && <p>Consultant-created scope from {task.origin_task_ids.length} earlier task(s).</p>}
    {Object.entries(task.effort_assumptions).map(([id, item]) => <p key={id}>Source #{id} · consultant assumption · {item.effort_type}. {item.reason} {item.calculation_reason}</p>)}
    {!!task.gaps.length && <div><h4 className="font-medium">Open gaps</h4><TextList items={task.gaps} /></div>}
    {!!task.notes.length && <div><h4 className="font-medium">Decision notes</h4><TextList items={task.notes} /></div>}
    {!readOnly && <fieldset disabled={busy} className="space-y-2">
      <div className="flex flex-wrap items-center gap-2">
        {['select', 'reject', 'defer', 'annotate'].map(action => <Button key={action} size="sm" variant="secondary"
          onClick={() => save({ action, task_id: task.id })}>{action[0].toUpperCase() + action.slice(1)}</Button>)}
        <label><input type="checkbox" checked={merged} onChange={toggleMerge} /> Mark for merge</label>
      </div>
      <details><summary className="cursor-pointer">Choose participants</summary>
        <form className="mt-2 space-y-2" onSubmit={event => {
          event.preventDefault();
          save({ action: 'participants', task_id: task.id, participant_ids: new FormData(event.currentTarget).getAll('people').map(Number) });
        }}>
          <div className="max-h-56 space-y-1 overflow-y-auto">{people.map(person => <label className="block" key={person.id}>
            <input type="checkbox" name="people" value={person.id} defaultChecked={task.participant_ids.includes(person.id)} /> {person.name || 'Employee'} #{person.id}
            {sources.some(source => source.employee_id === person.id) ? ' · linked evidence' : ' · outside linked evidence'}
            {!person.discovery_consent_recorded && ' · Discovery consent unrecorded'}
          </label>)}</div>
          <Button size="sm" type="submit">Save participants</Button>
        </form>
      </details>
      <SplitForm task={task} sources={sources} save={save} />
      {sources.length > 0 && <EffortForm task={task} sources={sources} save={save} />}
    </fieldset>}
  </section>;
}

function SplitForm({ task, sources, save }: { task: ReviewTask; sources: TaskSource[]; save: Save }) {
  const [count, setCount] = useState(2);
  return <details><summary className="cursor-pointer">Split task</summary>
    <form className="mt-2 space-y-2" onSubmit={event => {
      event.preventDefault();
      const data = new FormData(event.currentTarget);
      const children = Array.from({ length: count }, (_, index) => ({
        title: String(data.get(`title${index}`)), source_ids: data.getAll(`sources${index}`).map(Number),
      }));
      save({ action: 'split', task_id: task.id, children });
    }}>
      <p>Keep every original source across the child tasks. Mark a source in multiple children if it covers more than one scope.</p>
      {Array.from({ length: count }, (_, index) => <div key={index}>
        <label>Child {index + 1} title <input className={field} required maxLength={255} name={`title${index}`} /></label>
        {sources.map(source => <label className="block" key={source.id}>
          <input type="checkbox" name={`sources${index}`} value={source.id} /> {sourceLabel(source)}
        </label>)}
      </div>)}
      <Button variant="secondary" size="sm" disabled={count >= 20} onClick={() => setCount(count + 1)}>Add child scope</Button>{' '}
      {count > 2 && <Button variant="secondary" size="sm" onClick={() => setCount(count - 1)}>Remove last scope</Button>}{' '}
      <Button type="submit" size="sm">Save split</Button>
    </form>
  </details>;
}

function RelationshipForm({ sources, save, busy }: { sources: TaskSource[]; save: Save; busy: boolean }) {
  return <details><summary className="cursor-pointer">Record relationship judgment</summary>
    <form className="mt-2 space-y-2" onSubmit={event => {
      event.preventDefault();
      const data = new FormData(event.currentTarget);
      save({ action: 'relationship', source_ids: [Number(data.get('first')), Number(data.get('second'))], classification: String(data.get('classification')) });
    }}>
      <p>Recorded separately from Discovery evidence. Linked clarification requests stay open.</p>
      <fieldset disabled={busy} className="flex flex-wrap items-end gap-2">
        {['first', 'second'].map(key => <label className="block" key={key}>{key === 'first' ? 'First source' : 'Second source'} <select className={field} name={key} required defaultValue="">
          <option value="" disabled>Choose source</option>
          {sources.map(source => <option key={source.id} value={source.id}>{sourceLabel(source)}</option>)}
        </select></label>)}
        <label>Classification <select className={field} name="classification" defaultValue="UNRESOLVED">
          {['SHARED_IDENTICAL', 'SHARED_VARIANT', 'DISTINCT', 'UNRESOLVED'].map(value => <option key={value} value={value}>{words(value)}</option>)}
        </select></label>
        <Button type="submit" size="sm">Save relationship</Button>
      </fieldset>
    </form>
  </details>;
}

function EffortForm({ task, sources, save }: { task: ReviewTask; sources: TaskSource[]; save: Save }) {
  const [type, setType] = useState('active');
  return <details><summary className="cursor-pointer">Record effort assumption</summary>
    <form className="mt-2 space-y-2" onSubmit={event => {
      event.preventDefault();
      const data = new FormData(event.currentTarget);
      const range = (key: string) => ({ min: Number(data.get(`${key}-min`)), max: Number(data.get(`${key}-max`)), unit: String(data.get(`${key}-unit`)) });
      save({ action: 'effort', task_id: task.id, source_id: Number(data.get('source')), effort_type: type, frequency: range('frequency'), duration: range('duration') });
    }}>
      <label>Source <select className={field} name="source">{sources.map(source => <option key={source.id} value={source.id}>{sourceLabel(source)}</option>)}</select></label>{' '}
      <label>Effort type <select className={field} value={type} onChange={event => setType(event.target.value)}>
        <option value="active">Active work</option><option value="waiting">Waiting</option><option value="unknown">Unknown</option><option value="reported">Restore reported effort</option>
      </select></label>
      {['active', 'waiting'].includes(type) && Object.entries({ frequency: ['per_day', 'per_week', 'per_month', 'per_quarter', 'per_year'], duration: ['minutes', 'hours', 'days'] }).map(([key, units]) => <div className="flex flex-wrap gap-2" key={key}>
        {['min', 'max'].map(bound => <label key={bound}>{key} {bound} <input className={`${field} w-24`} type="number" min="0" step="any" required name={`${key}-${bound}`} /></label>)}
        <label>{key} unit <select className={field} name={`${key}-unit`}>{units.map(unit => <option key={unit} value={unit}>{words(unit)}</option>)}</select></label>
      </div>)}
      <div><Button type="submit" size="sm">Save effort assumption</Button></div>
    </form>
  </details>;
}
