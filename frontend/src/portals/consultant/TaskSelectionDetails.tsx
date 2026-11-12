import { Check, UsersRound } from 'lucide-react';
import { Badge, Button } from '../../components/ui';
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from '../../components/shadcn/sheet';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '../../components/shadcn/tabs';
import type { ReviewParticipant, ReviewTask, SelectionReview, TaskSource } from '../../lib/taskSelection';
import { ProposalEvidence, RelationshipEvidence, TextList, words } from './TaskSelectionEvidence';
import { EffortForm, RelationshipForm, SplitForm, type Save } from './TaskSelectionForms';

export type ParticipantFeedback = { taskId: string; message: string; error?: boolean };
export type DetailTab = 'participants' | 'evidence' | 'decisions';

export function linkedParticipants(sources: TaskSource[], people: ReviewParticipant[]) {
  const employeeIds = new Set(sources.map(source => source.employee_id));
  return [...new Map(people.filter(person => employeeIds.has(person.id)).map(person => [person.id, person])).values()];
}

export const participantName = (person: ReviewParticipant) => person.name || 'Unnamed employee';

export function TaskSelectionDetails({ task, initialTab, review, readOnly, busy, feedback, marked, toggleMerge, onClose, onHistory, save }: {
  task: ReviewTask; initialTab: DetailTab; review: SelectionReview; readOnly: boolean; busy: boolean;
  feedback?: ParticipantFeedback; marked: boolean; toggleMerge: () => void; onClose: () => void; onHistory: () => void; save: Save;
}) {
  const sources = review.sources.filter(source => task.source_ids.includes(source.id));
  const linked = linkedParticipants(sources, review.eligible_participants);
  const assigned = linked.filter(person => task.participant_ids.includes(person.id));
  const unavailable = assigned.length !== task.participant_ids.length;
  const relationships = review.relationships.filter(pair => pair.source_ids.some(id => task.source_ids.includes(id)));
  const judgments = Object.values(review.snapshot.relationship_overrides).filter(pair => pair.source_ids.some(id => task.source_ids.includes(id)));
  const relationshipIds = new Set([...task.source_ids, ...relationships.flatMap(pair => pair.source_ids)]);
  return <Sheet open onOpenChange={open => { if (!open && !busy) onClose(); }}>
    <SheetContent aria-label={task.title} className="flex w-full flex-col gap-0 overflow-hidden p-0 sm:max-w-xl">
      <SheetHeader className="border-b border-border px-5 py-5 pr-12 text-left sm:px-6">
        <SheetTitle className="break-words font-display text-xl">{task.title}</SheetTitle>
        <SheetDescription>Review participants, Discovery evidence and consultant decisions.</SheetDescription>
      </SheetHeader>
      <Tabs defaultValue={initialTab} className="flex min-h-0 flex-1 flex-col">
        <div className="border-b border-border px-5 py-3 sm:px-6">
          <TabsList aria-label="Task details" className="grid w-full grid-cols-3">
            <TabsTrigger value="participants">Participants</TabsTrigger>
            <TabsTrigger value="evidence">Evidence</TabsTrigger>
            <TabsTrigger value="decisions">Decisions</TabsTrigger>
          </TabsList>
        </div>
        <div className="min-h-0 flex-1 overflow-y-auto px-5 pb-6 sm:px-6">
          <TabsContent value="participants" className="space-y-4 text-sm">
            <h3 className="flex items-center gap-2 font-semibold"><UsersRound className="size-4 text-muted-foreground" aria-hidden /> Linked employees</h3>
            <p className="text-muted-foreground">Employees appear here when their Discovery evidence is linked to this task.</p>
            {unavailable && <p className="rounded-lg border border-warning/30 bg-warning/10 p-3">A previously saved participant is no longer eligible. Review and save the current list to update the assignment.</p>}
            {readOnly ? <p>{assigned.map(participantName).join(', ') || 'No participants assigned.'}</p> :
              <form className="space-y-4" onSubmit={event => {
                event.preventDefault();
                save({ action: 'participants', task_id: task.id, participant_ids: new FormData(event.currentTarget).getAll('people').map(Number) });
              }}>
                <fieldset disabled={busy} className="space-y-2">
                  {linked.map(person => <label className="flex cursor-pointer flex-wrap items-center gap-2 rounded-lg border border-border p-3" key={person.id}>
                    <input type="checkbox" className="size-4 accent-primary" name="people" value={person.id} defaultChecked={task.participant_ids.includes(person.id)} />
                    <span className="font-medium">{participantName(person)}</span>
                    {linked.filter(other => participantName(other) === participantName(person)).length > 1 &&
                      <span className="text-muted-foreground">· Employee #{person.id}</span>}
                    {!person.discovery_consent_recorded && <Badge variant="warning">Discovery consent unrecorded</Badge>}
                  </label>)}
                  {!linked.length && <p className="rounded-lg border border-dashed border-border p-4 text-muted-foreground">No eligible employees have Discovery evidence linked to this task.</p>}
                  {(linked.length > 0 || unavailable) && <Button type="submit" size="sm" loading={busy}>Save participants</Button>}
                </fieldset>
                {feedback && <p role={feedback.error ? 'alert' : 'status'} className={feedback.error ? 'text-destructive' : 'font-medium'}>
                  {!feedback.error && !busy && <Check className="mr-1 inline size-4 text-success" aria-hidden />}{feedback.message}
                </p>}
              </form>}
          </TabsContent>
          <TabsContent value="evidence" className="space-y-4 text-sm">
            <section className="space-y-2">
              <h3 className="font-semibold">What still needs review</h3>
              <TextList items={[...new Set(task.gaps)]} />
              {relationships.map(pair => <RelationshipEvidence key={pair.source_ids.join(':')} relationship={pair} sources={review.sources} />)}
            </section>
            <section className="space-y-2 border-t border-border pt-4">
              <h3 className="font-semibold">Original recommendations</h3>
              {review.proposals.filter(proposal => task.proposal_ids.includes(proposal.id)).map(proposal =>
                <ProposalEvidence key={proposal.id} proposal={proposal} sources={review.sources} />)}
              {!task.proposal_ids.length && <p className="text-muted-foreground">This task was added during the consultant review.</p>}
            </section>
            <section className="space-y-2 border-t border-border pt-4">
              <h3 className="font-semibold">Consultant judgments</h3>
              {judgments.map(judgment => <p key={judgment.source_ids.join(':')}>
                {judgment.source_ids.map(id => review.sources.find(source => source.id === id)?.name).join(' and ')} · {words(judgment.classification)}. {judgment.reason}
              </p>)}
              {Object.entries(task.effort_assumptions).map(([id, item]) => <p key={id}>
                {sources.find(source => source.id === Number(id))?.name} · {item.effort_type}. {item.reason} {item.calculation_reason}
              </p>)}
              {!readOnly && <fieldset disabled={busy} className="space-y-3">
                {relationshipIds.size > 1 && <RelationshipForm sources={review.sources.filter(source => relationshipIds.has(source.id))} busy={busy} save={save} />}
                {sources.length > 0 && <EffortForm task={task} sources={sources} save={save} />}
              </fieldset>}
            </section>
          </TabsContent>
          <TabsContent value="decisions" className="space-y-4 text-sm">
            <section className="space-y-2 rounded-lg border border-border p-4">
              <h3 className="font-semibold">Latest decision</h3>
              <p>{task.decision_reason || 'No selection decision recorded yet.'}</p>
              {task.participant_reason && <p className="text-muted-foreground">{task.participant_reason}</p>}
              {!!task.origin_task_ids.length && <p className="text-muted-foreground">Built from {task.origin_task_ids.length} earlier task scope(s).</p>}
            </section>
            <section className="space-y-2">
              <h3 className="font-semibold">Decision notes</h3>
              <TextList items={task.notes} />
              <Button type="button" variant="secondary" size="sm" onClick={onHistory}>Open review history</Button>
            </section>
            {!readOnly && <fieldset disabled={busy} className="space-y-3 border-t border-border pt-4">
              <div className="flex flex-wrap gap-2">
                {([
                  { action: 'select', status: 'selected', label: 'Select' },
                  { action: 'reject', status: 'rejected', label: 'Reject' },
                  { action: 'defer', status: 'deferred', label: 'Defer' },
                ]).filter(decision => decision.status !== task.status).map(({ action, label }) =>
                  <Button key={action} type="button" size="sm" variant={action === 'select' ? 'primary' : 'secondary'}
                    onClick={() => save({ action, task_id: task.id })}>{label}</Button>)}
              </div>
              <Button type="button" size="sm" variant="secondary" onClick={() => save({ action: 'annotate', task_id: task.id })}>Add decision note</Button>
              <label className="block"><input type="checkbox" checked={marked} onChange={toggleMerge} /> Mark for merge</label>
              <SplitForm task={task} sources={sources} save={save} />
            </fieldset>}
          </TabsContent>
        </div>
      </Tabs>
    </SheetContent>
  </Sheet>;
}
