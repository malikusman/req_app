import { useEffect, useState } from 'react';
import { Link, useParams, useSearchParams } from 'react-router-dom';
import { Badge, Button, Card, Modal, useToast } from '../../components/ui';
import { AlertTriangle, ArrowDown, ArrowUp, Check, UsersRound } from 'lucide-react';
import { DashboardShell } from '../../components/ui/DashboardShell';
import { api } from '../../lib/api';
import { useConsultantToken } from '../../lib/auth';
import type { Proposal, Relationship, ReviewCommand, ReviewParticipant, ReviewTask, SelectionReview, SelectionRun, TaskSource } from '../../lib/taskSelection';
import { ProposalEvidence, RelationshipEvidence, sourceLabel, TextList, words, workload } from './TaskSelectionEvidence';

const field = 'rounded-md border border-border bg-background px-2 py-1 text-foreground';
type Save = (command: ReviewCommand) => void;
type Feedback = { taskId: string; message: string; error?: boolean };
const actionLabels: Record<string, string> = {
  select: 'Select task', reject: 'Reject task', defer: 'Defer task', annotate: 'Add decision note',
  reorder: 'Save task order', add: 'Add task', merge: 'Merge tasks', split: 'Split task',
  relationship: 'Save relationship judgment', effort: 'Save effort assumption', capacity: 'Save capacity', finalize: 'Finalize selection',
};

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
  const [pending, setPending] = useState<ReviewCommand>();
  const [reason, setReason] = useState('');
  const [saveError, setSaveError] = useState('');
  const [feedback, setFeedback] = useState<Feedback>();
  const { toast } = useToast();
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
    setPending(undefined);
    setFeedback(undefined);
    if (!token || !run) return;
    let active = true;
    api.consultantTaskSelection(token, companyId, run, version)
      .then(data => { if (active) setReview(data); })
      .catch(err => { if (active) setError(err.message); });
    return () => { active = false; };
  }, [companyId, token, run, version, reload]);

  const current = review && String(review.run.id) === run && (version === null || String(review.version) === version) ? review : undefined;
  const readOnly = !current || current.status === 'finalized' || version !== null;
  async function persist(command: ReviewCommand, decisionReason?: string) {
    if (!token || !run || !current || readOnly || busy) return;
    setBusy(true);
    setSaveError('');
    const participantTask = command.action === 'participants' ? command.task_id : undefined;
    setFeedback(participantTask ? { taskId: participantTask, message: 'Saving participants…' } : undefined);
    try {
      setReview(await api.consultantTaskSelectionCommand(token, companyId, run, {
        ...command, expected_version: current.version, reason: decisionReason,
      }));
      setPending(undefined);
      if (participantTask) {
        setFeedback({ taskId: participantTask, message: 'Participants saved.' });
      } else {
        toast({ title: command.action === 'finalize' ? 'Selection finalized' : 'Decision saved', variant: 'success' });
      }
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Could not save the decision.';
      if (participantTask) setFeedback({ taskId: participantTask, message, error: true });
      else setSaveError(message);
    } finally {
      setBusy(false);
    }
  }

  function save(command: ReviewCommand) {
    if (command.action === 'participants') {
      void persist(command);
      return;
    }
    setReason('');
    setSaveError('');
    setPending(command);
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

  return <DashboardShell title="Deep Dive Task Selection" description="Choose which tasks to investigate and who can speak to the work.">
    <div className="flex flex-wrap items-center justify-between gap-3 text-sm">
      <Link className="font-medium text-primary hover:underline" to={base}>← Company overview</Link>
      <Button size="sm" variant="ghost" disabled={busy} onClick={() => { setError(''); setReload(value => value + 1); }}>Reload review</Button>
    </div>
    {error && <p role="alert" className="rounded-md border border-warning p-3 text-sm">{error}</p>}
    {runs && !runs.length && !run && <Card title="No recommendations yet"><p>Run Task Intelligence for this company to start a review.</p></Card>}
    {!current && !error && (!runs || runs.length > 0 || run) && <p role="status">Loading task selection…</p>}
    {current && <ReviewContent key={`${current.run.id}:${version ?? 'latest'}`}
      review={current} readOnly={readOnly} busy={busy} feedback={feedback} save={save} />}
    {run && <details className="rounded-xl border border-border bg-card p-4 text-sm">
      <summary className="cursor-pointer font-semibold">Recommendation versions and review history</summary>
      <div className="mt-4 flex flex-wrap items-center gap-4">
      <label>Task Intelligence run <select className={field} value={run} disabled={busy} onChange={event => {
        setError(''); setSearch({ run: event.target.value });
      }}>
        {!runs?.some(item => String(item.id) === run) && <option value={run}>Run #{run}</option>}
        {runs?.map(item => <option key={item.id} value={item.id}>Version {item.version} · run #{item.id}</option>)}
      </select></label>
      {!!runList?.before && <Button variant="secondary" size="sm" onClick={loadOlderRuns}>Load older runs</Button>}
      {current && <label>Review revision <select className={field} value={version ?? ''} disabled={busy} onChange={event => {
        setError(''); setSearch(event.target.value ? { run: run!, version: event.target.value } : { run: run! });
      }}>
        <option value="">Latest (v{current.latest_version})</option><option value="0">Initial proposals</option>
        {current.history.map(item => <option key={item.version} value={item.version}>v{item.version} · {item.action}</option>)}
      </select></label>}
      </div>
      {current && <ol className="mt-4 space-y-2 text-muted-foreground">
        {current.history.filter(item => item.version <= current.version).map(item => <li key={item.version}>
          <strong className="capitalize text-foreground">{words(item.action)}</strong> · v{item.version} · consultant #{item.consultant_user_id} · {new Date(item.created_at).toLocaleString()} · {item.reason}
        </li>)}
        {!current.version && <li>No consultant decisions yet.</li>}
      </ol>}
    </details>}
    {pending && <Modal open title={actionLabels[pending.action]} onClose={() => { if (!busy) setPending(undefined); }}>
      <form className="space-y-4 text-sm" onSubmit={event => {
        event.preventDefault();
        if (reason.trim()) void persist(pending, reason.trim());
        else setSaveError('Enter a reason for this decision.');
      }}>
        {pending.action === 'finalize' && <p>Approve {current?.snapshot.selected_order.length} selected task(s) for Deep Dive planning? Finalizing locks this review and keeps any unresolved gaps with the selection.</p>}
        <label className="block font-medium">Reason
          <textarea autoFocus className={`${field} mt-1 block w-full`} rows={3} maxLength={2000} required value={reason} onChange={event => setReason(event.target.value)} />
        </label>
        {saveError && <p role="alert" className="text-destructive">{saveError}</p>}
        <div className="flex justify-end gap-2">
          <Button type="button" variant="secondary" disabled={busy} onClick={() => setPending(undefined)}>Cancel</Button>
          <Button type="submit" loading={busy}>{pending.action === 'finalize' ? 'Confirm finalization' : 'Save decision'}</Button>
        </div>
      </form>
    </Modal>}
  </DashboardShell>;
}

function ReviewContent({ review, readOnly, busy, feedback, save }: {
  review: SelectionReview; readOnly: boolean; busy: boolean; feedback?: Feedback; save: Save;
}) {
  const { snapshot, sources, eligible_participants: people } = review;
  const [merge, setMerge] = useState<string[]>([]);
  const live = snapshot.tasks.filter(task => !['merged', 'split'].includes(task.status));
  const selected = snapshot.selected_order.flatMap(id => live.filter(task => task.id === id));
  const tasks = [...selected, ...live.filter(task => task.status !== 'selected')];
  const marked = merge.filter(id => live.some(task => task.id === id));
  const replaced = snapshot.tasks.filter(task => !live.includes(task));
  const unresolved = tasks.filter(task => task.gaps.some(gap => gap !== 'No participant selected.' || task.status === 'selected')).length;
  const viewStatus = snapshot.final_selection ? (snapshot.final_selection.provisional ? 'Finalized with unresolved gaps' : 'Finalized')
    : readOnly ? 'Read-only revision' : 'Draft review';

  function move(index: number, offset: number) {
    const task_ids = [...snapshot.selected_order];
    [task_ids[index], task_ids[index + offset]] = [task_ids[index + offset], task_ids[index]];
    save({ action: 'reorder', task_ids });
  }

  return <div className="space-y-6">
    <Card>
      <div className="space-y-3 text-sm">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <p role="status" className="font-semibold">{viewStatus}</p>
          {!readOnly && <Button disabled={!selected.length || busy} onClick={() => save({ action: 'finalize' })}>Finalize selection</Button>}
        </div>
        <dl className="grid grid-cols-3 gap-2 sm:gap-4">
          {[
            { label: 'Suggested', count: review.proposals.filter(proposal => proposal.rank !== null).length },
            { label: 'Selected', count: selected.length },
            { label: 'Unresolved', count: unresolved },
          ].map(({ label, count }) => <div key={label} className="rounded-xl border border-border bg-background p-3 sm:p-4">
            <dt className="text-muted-foreground">{label}</dt><dd className="text-2xl font-semibold tabular-nums">{count}</dd>
          </div>)}
        </dl>
        <details className="border-t border-border pt-3">
          <summary className="cursor-pointer font-medium">Interview capacity · {snapshot.sampling.planned_interviews} planned{snapshot.sampling.available_slots !== null ? ` / ${snapshot.sampling.available_slots} available` : ''}{snapshot.sampling.gaps.length ? ' · needs review' : ''}</summary>
          <div className="mt-3 space-y-3">
          <TextList items={snapshot.sampling.gaps} />
          {!readOnly && <fieldset disabled={busy}>
          <form className="flex flex-wrap items-end gap-2" onSubmit={event => {
            event.preventDefault();
            const value = new FormData(event.currentTarget).get('slots');
            save({ action: 'capacity', slots: value === '' ? null : Number(value) });
          }}>
            <label>Available interview slots <input className={`${field} w-24`} name="slots" type="number" min="0" max="1000" defaultValue={snapshot.sampling.available_slots ?? ''} /></label>
            <Button variant="secondary" size="sm" type="submit">Save capacity</Button>
          </form>
          </fieldset>}
          </div>
        </details>
      </div>
    </Card>

    <section aria-label="Tasks" className="space-y-3 text-sm">
        <h2 className="text-lg font-semibold">Tasks <span className="font-normal text-muted-foreground">({tasks.length})</span></h2>
        {!readOnly && <details className="rounded-xl border border-border bg-card p-4">
          <summary className="cursor-pointer font-medium">Manage tasks{marked.length > 0 ? ` · ${marked.length} marked for merge` : ''}</summary>
          <fieldset disabled={busy} className="mt-3 space-y-3">
            <TaskTitleForm action="add" sources={sources} save={save} />
            <TaskTitleForm action="merge" selected={marked} save={save} />
          </fieldset>
        </details>}
        {!tasks.length && <p className="text-muted-foreground">There are no tasks in this review yet.</p>}
        {tasks.map(task => <TaskCard key={task.id} task={task} sources={sources}
          proposals={review.proposals.filter(proposal => task.proposal_ids.includes(proposal.id))}
          relationships={review.relationships.filter(pair => pair.source_ids.some(id => task.source_ids.includes(id)))}
          people={people} readOnly={readOnly} busy={busy} save={save}
          feedback={feedback?.taskId === task.id ? feedback : undefined} merged={marked.includes(task.id)}
          move={task.status === 'selected' ? offset => move(snapshot.selected_order.indexOf(task.id), offset) : undefined}
          canMoveUp={snapshot.selected_order.indexOf(task.id) > 0}
          canMoveDown={snapshot.selected_order.indexOf(task.id) < selected.length - 1} toggleMerge={() => {
            setMerge(list => list.includes(task.id) ? list.filter(id => id !== task.id) : [...list, task.id]);
          }} />)}
        {!!replaced.length && <details className="rounded-xl border border-border p-4"><summary className="cursor-pointer font-medium">Earlier task scopes</summary><ul className="mt-2 list-disc pl-5">
          {replaced.map(task => <li key={task.id}>{task.title} · {task.status} · {task.replacement_reason}</li>)}
        </ul></details>}
    </section>
    <details className="rounded-xl border border-border bg-card p-4 text-sm">
      <summary className="cursor-pointer font-semibold">Original recommendations and relationship judgments</summary>
      <div className="mt-3 space-y-3">
        <p className="text-muted-foreground">Evaluation mode · {words(review.run.evaluation_mode)}</p>
        {review.proposals.map(proposal => <ProposalEvidence key={proposal.id} proposal={proposal} sources={sources} />)}
        {Object.values(snapshot.relationship_overrides).map(override => <p key={override.source_ids.join(':')}>
          Consultant judgment · {override.source_ids.map(id => sources.find(source => source.id === id)?.name).join(' and ')} · {words(override.classification)}. {override.reason}
        </p>)}
        {!readOnly && sources.length > 1 && <RelationshipForm sources={sources} save={save} busy={busy} />}
      </div>
    </details>
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

function TaskCard({ task, sources, proposals, relationships, people, readOnly, busy, save, feedback, merged, toggleMerge, move, canMoveUp, canMoveDown }: {
  task: ReviewTask; sources: TaskSource[]; proposals: Proposal[]; relationships: Relationship[]; people: ReviewParticipant[];
  readOnly: boolean; busy: boolean; save: Save; feedback?: Feedback; merged: boolean; toggleMerge: () => void;
  move?: (offset: number) => void; canMoveUp: boolean; canMoveDown: boolean;
}) {
  const taskSources = sources.filter(source => task.source_ids.includes(source.id));
  const linked = people.filter(person => taskSources.some(source => source.employee_id === person.id));
  const assigned = linked.filter(person => task.participant_ids.includes(person.id));
  const hasUnavailableParticipant = assigned.length !== task.participant_ids.length;
  const suggestion = proposals.find(proposal => proposal.rank !== null);
  const priorities = ['high', 'medium', 'low'];
  const priority = priorities.find(value => proposals.some(proposal => proposal.priority === value));
  const overlap = relationships.some(pair => pair.classification === 'UNRESOLVED' || pair.kind === 'uncertain') ||
    task.gaps.some(gap => /overlap|unresolved relationship/i.test(gap) && !gap.startsWith('Active workload'));
  const hasClarification = relationships.some(pair => pair.clarification_request?.status === 'open');
  const label = (person: ReviewParticipant) => person.name || 'Unnamed employee';
  return <section aria-label={task.title} className={`space-y-3 rounded-xl border bg-card p-4 sm:p-5 ${task.status === 'selected' ? 'border-primary/40' : 'border-border'}`}>
    <div className="flex flex-wrap items-start justify-between gap-3">
      <div className="min-w-0 space-y-2">
        <h3 className="break-words text-base font-semibold">{task.title}</h3>
        <div className="flex flex-wrap gap-1.5">
          <Badge className="capitalize" variant={task.status === 'selected' ? 'success' : 'neutral'}>{task.status === 'pending' ? 'To review' : task.status}</Badge>
          {suggestion && <Badge variant="info">Suggested · #{suggestion.rank}</Badge>}
          {priority && <Badge className="capitalize" variant={priority === 'high' ? 'warning' : 'neutral'}>{priority} priority</Badge>}
        </div>
      </div>
      {!readOnly && move && <div className="flex gap-1">
        <Button type="button" variant="ghost" size="sm" disabled={busy || !canMoveUp} onClick={() => move(-1)} aria-label={`Move ${task.title} up`} icon={<ArrowUp />} />
        <Button type="button" variant="ghost" size="sm" disabled={busy || !canMoveDown} onClick={() => move(1)} aria-label={`Move ${task.title} down`} icon={<ArrowDown />} />
      </div>}
    </div>
    <div className="flex flex-wrap gap-x-6 gap-y-1 text-muted-foreground">
      <p><strong className="text-foreground">Workload</strong> · {workload(task.effective_effort)}</p>
      <p><strong className="text-foreground">Participants</strong> · {assigned.map(label).join(', ') || 'None selected'}</p>
    </div>
    {(overlap || hasClarification || hasUnavailableParticipant) && <p className="flex items-start gap-2 rounded-md bg-warning/10 p-2">
      <AlertTriangle className="mt-0.5 size-4 shrink-0 text-warning" aria-hidden />
      <span>{overlap ? 'This task may overlap with other work.' : ''}{overlap && hasClarification ? ' ' : ''}{hasClarification ? 'Some facts need clarification.' : ''}{hasUnavailableParticipant && ' Review a previously saved participant who is no longer eligible for this task.'}</span>
    </p>}
    {!readOnly && <div className="flex flex-wrap items-center gap-2">
      {['select', 'reject', 'defer'].map(action => <Button key={action} type="button" size="sm" variant={action === 'select' ? 'primary' : 'secondary'}
        disabled={busy || ({ select: 'selected', reject: 'rejected', defer: 'deferred' }[action] === task.status)}
        onClick={() => save({ action, task_id: task.id })}>{action[0].toUpperCase() + action.slice(1)}</Button>)}
    </div>}
    {!readOnly && <details className="border-t border-border pt-3">
      <summary className="cursor-pointer font-medium"><UsersRound className="mr-2 inline size-4" aria-hidden />Choose participants</summary>
        <form className="mt-2 space-y-2" onSubmit={event => {
          event.preventDefault();
          save({ action: 'participants', task_id: task.id, participant_ids: new FormData(event.currentTarget).getAll('people').map(Number) });
        }}>
          <fieldset disabled={busy} className="space-y-2">
            {linked.length ? <div className="max-h-56 space-y-1 overflow-y-auto">{linked.map(person => <label className="flex flex-wrap items-center gap-2 rounded-md p-1" key={person.id}>
              <input type="checkbox" name="people" value={person.id} defaultChecked={task.participant_ids.includes(person.id)} />
              {label(person)}
              {linked.filter(other => label(other) === label(person)).length > 1 && <span className="text-muted-foreground">· Employee #{person.id}</span>}
              {!person.discovery_consent_recorded && <Badge variant="warning">Discovery consent unrecorded</Badge>}
            </label>)}</div> : <p className="text-muted-foreground">No eligible employees have Discovery evidence linked to this task.</p>}
            {(linked.length > 0 || hasUnavailableParticipant) && <Button size="sm" type="submit" disabled={busy}>Save participants</Button>}
          </fieldset>
          {feedback && <p role={feedback.error ? 'alert' : 'status'} className={feedback.error ? 'text-destructive' : 'font-medium'}>
            {!feedback.error && <Check className="mr-1 inline size-4" aria-hidden />}{feedback.message}
          </p>}
        </form>
    </details>}
    <details className="border-t border-border pt-3">
      <summary className="cursor-pointer font-medium">Evidence and options</summary>
      <div className="mt-3 space-y-3">
        {task.decision_reason && <p>{task.decision_reason}</p>}
        {task.participant_reason && <p>{task.participant_reason}</p>}
        {!!task.origin_task_ids.length && <p>Built from {task.origin_task_ids.length} earlier task scope(s).</p>}
        {!!task.gaps.length && <div><h4 className="font-medium">Open gaps</h4><TextList items={task.gaps} /></div>}
        {!!task.notes.length && <div><h4 className="font-medium">Decision notes</h4><TextList items={task.notes} /></div>}
        {relationships.map(pair => <RelationshipEvidence key={pair.source_ids.join(':')} relationship={pair} sources={sources} />)}
        {proposals.map(proposal => <ProposalEvidence key={proposal.id} proposal={proposal} sources={sources} />)}
        {Object.entries(task.effort_assumptions).map(([id, item]) => <p key={id}>{sources.find(source => source.id === Number(id))?.name} · consultant assumption · {item.effort_type}. {item.reason} {item.calculation_reason}</p>)}
        {!readOnly && <fieldset disabled={busy} className="space-y-3">
          <Button type="button" size="sm" variant="secondary" onClick={() => save({ action: 'annotate', task_id: task.id })}>Add decision note</Button>
          <label className="block"><input type="checkbox" checked={merged} onChange={toggleMerge} /> Mark for merge</label>
          <SplitForm task={task} sources={taskSources} save={save} />
          {taskSources.length > 0 && <EffortForm task={task} sources={taskSources} save={save} />}
        </fieldset>}
      </div>
    </details>
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
      <Button type="button" variant="secondary" size="sm" disabled={count >= 20} onClick={() => setCount(count + 1)}>Add child scope</Button>{' '}
      {count > 2 && <Button type="button" variant="secondary" size="sm" onClick={() => setCount(count - 1)}>Remove last scope</Button>}{' '}
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
