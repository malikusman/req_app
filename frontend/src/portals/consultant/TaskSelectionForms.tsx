import { useState } from 'react';
import { Button } from '../../components/ui';
import type { ReviewCommand, ReviewTask, TaskSource } from '../../lib/taskSelection';
import { sourceLabel, words } from './TaskSelectionEvidence';

export const field = 'max-w-full rounded-lg border border-border bg-background px-3 py-2 text-foreground';
export type Save = (command: ReviewCommand) => void;

function SourceChecks({ sources }: { sources: TaskSource[] }) {
  return <div className="space-y-1">{sources.map(source => <label className="block" key={source.id}>
    <input type="checkbox" name="sources" value={source.id} /> {sourceLabel(source)}
  </label>)}</div>;
}

export function TaskTitleForm({ action, selected = [], sources = [], save }: {
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

export function SplitForm({ task, sources, save }: { task: ReviewTask; sources: TaskSource[]; save: Save }) {
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

export function RelationshipForm({ sources, save, busy }: { sources: TaskSource[]; save: Save; busy: boolean }) {
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

export function EffortForm({ task, sources, save }: { task: ReviewTask; sources: TaskSource[]; save: Save }) {
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
