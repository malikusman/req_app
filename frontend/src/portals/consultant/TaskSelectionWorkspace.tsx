import { useState } from 'react';
import { AlertCircle, ArrowDown, ArrowUp, CalendarDays, CheckCircle2, ChevronRight, ClipboardList, Clock3, LockKeyhole, UsersRound } from 'lucide-react';
import { Badge, Button } from '../../components/ui';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '../../components/shadcn/tabs';
import type { ReviewTask, SelectionReview } from '../../lib/taskSelection';
import { linkedParticipants, participantName, TaskSelectionDetails, type DetailTab, type ParticipantFeedback } from './TaskSelectionDetails';
import { ProposalEvidence, TextList, words, workload } from './TaskSelectionEvidence';
import { field, RelationshipForm, TaskTitleForm, type Save } from './TaskSelectionForms';

const status = {
  selected: { label: 'Selected', variant: 'success', surface: 'border-success/25 border-l-success bg-success/[0.035]' },
  pending: { label: 'Pending', variant: 'neutral', surface: 'border-border border-l-border bg-card' },
  rejected: { label: 'Rejected', variant: 'neutral', surface: 'border-border border-l-muted-foreground/35 bg-muted/35' },
  deferred: { label: 'Deferred', variant: 'info', surface: 'border-border border-l-muted-foreground/35 bg-muted/35' },
} as const;
const priorities = ['high', 'medium', 'low'];
const panel = 'rounded-2xl border border-border bg-card p-4 sm:p-5';

export function TaskSelectionWorkspace({ review, readOnly, busy, feedback, onHistory, save }: {
  review: SelectionReview; readOnly: boolean; busy: boolean; feedback?: ParticipantFeedback; onHistory: () => void; save: Save;
}) {
  const [details, setDetails] = useState<{ id: string; tab: DetailTab }>();
  const [merge, setMerge] = useState<string[]>([]);
  const { snapshot, sources } = review;
  const live = snapshot.tasks.filter(task => task.status !== 'merged' && task.status !== 'split');
  const selected = snapshot.selected_order.flatMap(id => live.filter(task => task.id === id));
  const pending = live.filter(task => task.status === 'pending');
  const other = live.filter(task => task.status === 'rejected' || task.status === 'deferred');
  const replaced = snapshot.tasks.filter(task => !live.includes(task));
  const marked = merge.filter(id => live.some(task => task.id === id));
  const detailTask = live.find(task => task.id === details?.id);
  const clarifications = new Set(review.relationships.filter(pair => pair.clarification_request?.status === 'open')
    .flatMap(pair => pair.source_ids));
  const metrics = [
    { label: 'Suggested tasks', value: review.proposals.filter(proposal => proposal.rank !== null).length, icon: ClipboardList, color: 'bg-primary/10 text-primary' },
    { label: 'Selected for Deep Dive', value: selected.length, icon: CheckCircle2, color: 'bg-success/10 text-success' },
    { label: 'Need clarification', value: live.filter(task => task.source_ids.some(id => clarifications.has(id))).length, icon: AlertCircle, color: 'bg-warning/10 text-warning' },
  ];

  function move(id: string, offset: number) {
    const taskIds = [...snapshot.selected_order];
    const index = taskIds.indexOf(id);
    [taskIds[index], taskIds[index + offset]] = [taskIds[index + offset], taskIds[index]];
    save({ action: 'reorder', task_ids: taskIds });
  }

  function renderSection(title: string, tasks: ReviewTask[], empty: string) {
    return <section aria-label={title} className="space-y-3">
      <div className="flex items-center gap-2">
        <h2 className="text-base font-semibold sm:text-lg">{title}</h2><Badge>{tasks.length}</Badge>
      </div>
      {tasks.length ? <div className="space-y-2.5">{tasks.map(task => {
        const index = snapshot.selected_order.indexOf(task.id);
        return <TaskOverviewCard key={task.id} task={task} review={review} readOnly={readOnly} busy={busy}
          needsClarification={task.source_ids.some(id => clarifications.has(id))}
          open={tab => setDetails({ id: task.id, tab })}
          moveUp={index > 0 ? () => move(task.id, -1) : undefined}
          moveDown={index >= 0 && index < selected.length - 1 ? () => move(task.id, 1) : undefined}
          save={save} />;
      })}</div> : <p className="rounded-xl border border-dashed border-border bg-card px-4 py-5 text-sm text-muted-foreground">{empty}</p>}
    </section>;
  }

  return <div className="space-y-5 sm:space-y-7">
    <dl className="grid gap-3 sm:grid-cols-3">
      {metrics.map(({ label, value, icon: Icon, color }) => <div key={label} className="flex items-center gap-4 rounded-2xl border border-border bg-card p-4 sm:p-5">
        <span className={`grid size-10 shrink-0 place-items-center rounded-xl ${color}`}><Icon className="size-5" aria-hidden /></span>
        <div><dt className="text-sm text-muted-foreground">{label}</dt><dd className="text-2xl font-semibold tabular-nums">{value}</dd></div>
      </div>)}
    </dl>
    <div className="grid items-start gap-5 xl:grid-cols-[minmax(0,1fr)_19rem] xl:gap-7">
      <div className="min-w-0 space-y-4">
        <Tabs defaultValue="all">
          <TabsList aria-label="Filter tasks" className="h-auto min-h-10 w-full flex-wrap justify-start gap-1 sm:w-auto">
            <TabsTrigger value="all">All</TabsTrigger>
            <TabsTrigger value="selected">Selected</TabsTrigger>
            <TabsTrigger value="pending">Pending</TabsTrigger>
            <TabsTrigger value="other">Other Decisions</TabsTrigger>
          </TabsList>
          <TabsContent value="all" className="mt-4 space-y-6">
            {renderSection('Selected for Deep Dive', selected, 'Selected tasks will appear here in interview order.')}
            {renderSection('Pending review', pending, 'All tasks have a decision.')}
            {other.length > 0 && renderSection('Other decisions', other, 'No rejected or deferred tasks.')}
          </TabsContent>
          <TabsContent value="selected" className="mt-4">{renderSection('Selected for Deep Dive', selected, 'No tasks have been selected for Deep Dive yet.')}</TabsContent>
          <TabsContent value="pending" className="mt-4">{renderSection('Pending review', pending, 'All tasks have a decision.')}</TabsContent>
          <TabsContent value="other" className="mt-4">{renderSection('Other decisions', other, 'Rejected and deferred tasks will appear here.')}</TabsContent>
        </Tabs>
        <details className={panel}>
          <summary className="cursor-pointer text-sm font-semibold">Manage task scopes{marked.length > 0 ? ` · ${marked.length} marked for merge` : ''}</summary>
          <div className="mt-3 space-y-3 text-sm">
            {!readOnly && <fieldset disabled={busy} className="space-y-3">
              <TaskTitleForm action="add" sources={sources} save={save} />
              <TaskTitleForm action="merge" selected={marked} save={save} />
              {sources.length > 1 && <RelationshipForm sources={sources} busy={busy} save={save} />}
            </fieldset>}
            {replaced.length > 0 && <details><summary className="cursor-pointer font-medium">Earlier task scopes</summary><ul className="mt-2 list-disc space-y-1 pl-5">
              {replaced.map(task => <li key={task.id}>{task.title} · {task.status} · {task.replacement_reason}</li>)}
            </ul></details>}
            <details className="space-y-2">
              <summary className="cursor-pointer font-medium">Original recommendation set</summary>
              <p className="text-muted-foreground">Evaluation mode · {words(review.run.evaluation_mode)}</p>
              {review.proposals.map(proposal => <ProposalEvidence key={proposal.id} proposal={proposal} sources={sources} />)}
            </details>
            {Object.values(snapshot.relationship_overrides).map(override => <p key={override.source_ids.join(':')}>
              Consultant judgment · {override.source_ids.map(id => sources.find(source => source.id === id)?.name).join(' and ')} · {words(override.classification)}. {override.reason}
            </p>)}
          </div>
        </details>
      </div>
      <aside aria-label="Review readiness" className="grid gap-4 md:grid-cols-2 xl:grid-cols-1">
        <CapacityPanel review={review} readOnly={readOnly} busy={busy} save={save} />
        <section className={panel}>
          <h2 className="flex items-center gap-2 font-semibold"><LockKeyhole className="size-4 text-muted-foreground" aria-hidden /> Finalize selection</h2>
          {snapshot.final_selection ? <p role="status" className="mt-3 text-sm font-medium">
            {snapshot.final_selection.provisional ? 'Finalized with unresolved gaps' : 'Finalized'}
          </p> : readOnly ? <p role="status" className="mt-3 text-sm text-muted-foreground">Read-only revision</p> : <>
            <p className="mb-4 mt-2 text-sm text-muted-foreground">Approve the selected tasks when you’re ready. Any open gaps stay with the selection.</p>
            <Button type="button" className="w-full" disabled={!selected.length || busy} onClick={() => save({ action: 'finalize' })}>Finalize selection</Button>
            {!selected.length && <p className="mt-2 text-xs text-muted-foreground">Select at least one task to continue.</p>}
          </>}
        </section>
      </aside>
    </div>
    {detailTask && details && <TaskSelectionDetails key={detailTask.id} task={detailTask} initialTab={details.tab} review={review}
      readOnly={readOnly} busy={busy} feedback={feedback?.taskId === detailTask.id ? feedback : undefined}
      marked={marked.includes(detailTask.id)} toggleMerge={() => setMerge(ids => ids.includes(detailTask.id) ? ids.filter(id => id !== detailTask.id) : [...ids, detailTask.id])}
      onClose={() => setDetails(undefined)} onHistory={() => { setDetails(undefined); onHistory(); }} save={save} />}
  </div>;
}

function CapacityPanel({ review, readOnly, busy, save }: { review: SelectionReview; readOnly: boolean; busy: boolean; save: Save }) {
  const { planned_interviews: planned, available_slots: slots, gaps } = review.snapshot.sampling;
  return <section className={panel}>
    <h2 className="flex items-center gap-2 font-semibold"><CalendarDays className="size-4 text-muted-foreground" aria-hidden /> Interview capacity</h2>
    <dl className="my-3 grid grid-cols-2 gap-3 text-sm">
      <div><dt className="text-muted-foreground">Planned</dt><dd className="text-lg font-semibold">{planned}</dd></div>
      <div><dt className="text-muted-foreground">Available</dt><dd className="text-lg font-semibold">{slots ?? 'Not set'}</dd></div>
    </dl>
    {gaps.length > 0 && <div className="mb-3 rounded-lg bg-warning/10 p-3 text-sm"><TextList items={gaps} /></div>}
    {!readOnly && <form className="space-y-2" key={slots ?? 'unset'} onSubmit={event => {
      event.preventDefault();
      const value = new FormData(event.currentTarget).get('slots');
      save({ action: 'capacity', slots: value === '' ? null : Number(value) });
    }}>
      <label className="block text-sm font-medium">Available interview slots
        <input className={`${field} mt-1 block w-full`} name="slots" type="number" min="0" max="1000" defaultValue={slots ?? ''} disabled={busy} />
      </label>
      <Button variant="secondary" size="sm" type="submit" disabled={busy}>Save capacity</Button>
    </form>}
  </section>;
}

function TaskOverviewCard({ task, review, readOnly, busy, needsClarification, open, moveUp, moveDown, save }: {
  task: ReviewTask; review: SelectionReview; readOnly: boolean; busy: boolean; needsClarification: boolean;
  open: (tab: DetailTab) => void; moveUp?: () => void; moveDown?: () => void; save: Save;
}) {
  const style = status[task.status as keyof typeof status] ?? status.pending;
  const priority = priorities.find(value => review.proposals.some(proposal => task.proposal_ids.includes(proposal.id) && proposal.priority === value));
  const people = linkedParticipants(review.sources.filter(source => task.source_ids.includes(source.id)), review.eligible_participants);
  const assigned = people.filter(person => task.participant_ids.includes(person.id)).map(participantName);
  const overlap = task.gaps.some(gap => /overlap|unresolved relationship/i.test(gap) && !gap.startsWith('Active workload'));
  const warning = needsClarification ? 'Needs clarification' : overlap ? 'Possible overlap with other work' :
    task.participant_ids.length !== assigned.length ? 'An assigned participant needs review' : '';
  return <article aria-label={task.title} className={`space-y-3 rounded-xl border border-l-[3px] px-4 py-3.5 ${style.surface}`}>
    <div className="flex flex-wrap items-start justify-between gap-2">
      <div className="min-w-0">
        <h3 className="break-words font-semibold leading-snug">{task.title}</h3>
        {priority && <p className="mt-0.5 text-xs text-muted-foreground"><span className="capitalize">{priority}</span> AI priority</p>}
      </div>
      <Badge variant={style.variant}>{style.label}</Badge>
    </div>
    <div className="flex flex-wrap gap-x-4 gap-y-1 text-sm text-muted-foreground">
      <p className="flex items-start gap-1.5"><Clock3 className="mt-0.5 size-4 shrink-0" aria-hidden /> {workload(task.effective_effort)}</p>
      <p className="flex items-start gap-1.5"><UsersRound className="mt-0.5 size-4 shrink-0" aria-hidden />
        <span><span className="sr-only">Participants · </span>{assigned.join(', ') || 'No participants assigned'}</span></p>
    </div>
    {warning && <p className="inline-flex items-center gap-1.5 rounded-md bg-warning/10 px-2 py-1 text-xs font-medium text-warning"><AlertCircle className="size-3.5 shrink-0" aria-hidden />{warning}</p>}
    <div className="flex flex-wrap items-center justify-between gap-2">
      <div className="flex flex-wrap items-center gap-1.5">
        {!readOnly && task.status === 'pending' && ['select', 'reject', 'defer'].map(action =>
          <Button key={action} type="button" size="sm" variant={action === 'select' ? 'primary' : 'ghost'} disabled={busy} onClick={() => save({ action, task_id: task.id })}>
            {action[0].toUpperCase() + action.slice(1)}
          </Button>)}
        {!readOnly && task.status === 'selected' && <>
          <Button type="button" size="sm" variant="secondary" disabled={busy} onClick={() => open('participants')}>Choose participants</Button>
          {moveUp && <Button type="button" variant="ghost" size="sm" disabled={busy} onClick={moveUp} aria-label={`Move ${task.title} up`} icon={<ArrowUp />} />}
          {moveDown && <Button type="button" variant="ghost" size="sm" disabled={busy} onClick={moveDown} aria-label={`Move ${task.title} down`} icon={<ArrowDown />} />}
        </>}
      </div>
      <Button type="button" size="sm" variant="ghost" className="ml-auto" disabled={busy}
        onClick={() => open(task.status === 'rejected' || task.status === 'deferred' ? 'decisions' : 'evidence')}>
        Details <ChevronRight className="size-4" aria-hidden />
      </Button>
    </div>
  </article>;
}
