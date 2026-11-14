import { useEffect, useState } from 'react';
import { ArrowDown, ArrowLeft, ArrowUp, ClipboardList, LockKeyhole } from 'lucide-react';
import { Link, useBlocker, useParams, useSearchParams } from 'react-router-dom';
import { Badge, Button, Card, ConfirmDialog, EmptyState, ErrorNotice, Input, PageHeader, Select, Skeleton, Textarea, useToast } from '../../components/ui';
import { buttonVariants } from '../../components/shadcn/button';
import { api } from '../../lib/api';
import { useConsultantToken } from '../../lib/auth';
import type { PlanContent, PlanContext, PlanDetail, PlanStatus, PlanSummary } from '../../lib/deepDivePlan';
import { TextList, words, workload } from './TaskSelectionEvidence';

const labels: Record<PlanStatus, string> = {
  not_started: 'Not started', queued: 'Queued', generating: 'Generating', failed: 'Generation failed',
  draft: 'Draft', approved: 'Approved',
};
const message = (error: unknown) => error instanceof Error ? error.message : 'The request could not be completed.';

export function ConsultantDeepDivePlans() {
  const { companyId = '', runId = '' } = useParams();
  return <PlanWorkspace key={`${companyId}:${runId}`} companyId={companyId} runId={runId} />;
}

function PlanWorkspace({ companyId, runId }: { companyId: string; runId: string }) {
  const token = useConsultantToken();
  const [search, setSearch] = useSearchParams();
  const [list, setList] = useState<{ selection_version: number; tasks: PlanSummary[] }>();
  const [detail, setDetail] = useState<PlanDetail>();
  const [loadError, setLoadError] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [hasUnsavedEdits, setHasUnsavedEdits] = useState(false);
  const [reload, setReload] = useState(0);
  const { toast } = useToast();
  const task = search.get('task') ?? list?.tasks[0]?.task_id;
  const version = search.get('version') ?? undefined;
  const active = detail && detail.task_id === task &&
    (version ? String(detail.version) === version : detail.version === detail.latest_version) ? detail : undefined;
  const companyPath = `/consultant/companies/${companyId}`;
  const selectionPath = `${companyPath}/task-selection?run=${runId}`;
  const blocker = useBlocker(({ currentLocation, nextLocation }) => {
    if (!hasUnsavedEdits) return false;
    if (currentLocation.pathname !== nextLocation.pathname) return true;
    const next = new URLSearchParams(nextLocation.search);
    return (next.get('task') ?? list?.tasks[0]?.task_id) !== task || (next.get('version') ?? undefined) !== version;
  });

  useEffect(() => {
    if (!hasUnsavedEdits && blocker.state === 'blocked') blocker.reset();
  }, [hasUnsavedEdits, blocker]);

  useEffect(() => {
    if (!hasUnsavedEdits) return;
    function warnBeforeUnload(event: BeforeUnloadEvent) {
      event.preventDefault();
      event.returnValue = '';
    }
    window.addEventListener('beforeunload', warnBeforeUnload);
    return () => window.removeEventListener('beforeunload', warnBeforeUnload);
  }, [hasUnsavedEdits]);

  useEffect(() => {
    if (!token) return;
    let valid = true;
    api.consultantDeepDivePlans(token, companyId, runId).then(data => {
      if (valid) { setList(data); setLoadError(''); }
    }).catch(err => { if (valid) setLoadError(message(err)); });
    return () => { valid = false; };
  }, [token, companyId, runId, reload]);

  useEffect(() => {
    if (!token || !task) return;
    setError('');
    let valid = true;
    let timer: ReturnType<typeof setTimeout>;
    function read() {
      if (!token || !task) return;
      api.consultantDeepDivePlan(token, companyId, runId, task, version).then(data => {
        if (!valid) return;
        setDetail(data);
        setError('');
        setList(previous => previous && ({
          ...previous, tasks: previous.tasks.map(item => item.task_id === task ? { ...item, status: data.status } : item),
        }));
        if (!version && ['queued', 'generating'].includes(data.status) && !data.retry_available) {
          timer = setTimeout(read, 2500);
        }
      }).catch(err => { if (valid) setError(message(err)); });
    }
    read();
    return () => { valid = false; clearTimeout(timer); };
  }, [token, companyId, runId, task, version, reload]);

  async function command(action: 'generate' | 'edit' | 'approve', reason?: string, content?: PlanContent) {
    if (!token || !task || !active || version || busy) return false;
    setBusy(true);
    setError('');
    try {
      const body = action === 'generate' ? undefined : { expected_version: active.version!, reason: reason ?? '', content };
      const result = await api.consultantDeepDivePlanCommand(token, companyId, runId, task, action, body);
      setDetail(result);
      setList(previous => previous && ({
        ...previous, tasks: previous.tasks.map(item => item.task_id === task ? { ...item, status: result.status } : item),
      }));
      if (action === 'generate') setReload(value => value + 1);
      else {
        setHasUnsavedEdits(false);
        toast({ title: action === 'edit' ? 'Plan version saved' : 'Plan approved', variant: 'success' });
      }
      return true;
    } catch (err) {
      setError(message(err));
      return false;
    } finally {
      setBusy(false);
    }
  }

  function switchTask(taskId: string) {
    if (taskId !== task || version) setSearch({ task: taskId });
  }

  return <div className="space-y-6">
    <PageHeader className="mb-0" title="Prepare interview plans"
      description="Review and approve one interview plan for each selected task."
      breadcrumbs={[{ label: 'Company overview', href: companyPath }, { label: 'Task selection', href: selectionPath }, { label: 'Deep Dive plans' }]}
      actions={<Link className={buttonVariants({ size: 'sm', variant: 'secondary', className: 'sm:hidden' })} to={selectionPath}>
        <ArrowLeft aria-hidden /> Task selection
      </Link>} />
    {list && <p className="text-xs text-muted-foreground">Finalized selection · revision {list.selection_version}</p>}
    {loadError && <ErrorNotice message={loadError} retryLabel="Reload" onRetry={() => { setLoadError(''); setReload(value => value + 1); }} />}
    {!list && !loadError && <div role="status" aria-label="Loading selected tasks"><Skeleton variant="card" /></div>}
    {list && !list.tasks.length && <EmptyState icon={ClipboardList} title="This selection has no tasks." />}
    {!!list?.tasks.length && <div className="grid items-start gap-5 lg:grid-cols-[16rem_minmax(0,1fr)]">
      <div className="lg:hidden">
        <Select label="Selected task" value={task} disabled={busy} onChange={event => switchTask(event.target.value)}
          options={list.tasks.map(item => ({ value: item.task_id, label: `${item.title} · ${labels[item.status]}` }))} />
      </div>
      <nav aria-label="Selected tasks" className="hidden space-y-2 rounded-2xl border border-border bg-card p-3 lg:block">
        <h2 className="px-2 py-1 text-sm font-semibold">Selected tasks</h2>
        {list.tasks.map(item => <button key={item.task_id} type="button" aria-current={item.task_id === task ? 'true' : undefined}
          disabled={busy} onClick={() => switchTask(item.task_id)}
          className={`block w-full rounded-lg border p-2.5 text-left text-sm ${item.task_id === task ? 'border-primary/30 bg-primary/10' : 'border-transparent hover:bg-muted'}`}>
          <span className="block font-medium">{item.title}</span><span className="text-xs text-muted-foreground">{labels[item.status]}</span>
        </button>)}
      </nav>
      <div className="min-w-0 space-y-4">
        {error && !active?.content && <ErrorNotice message={error} retryLabel="Reload" onRetry={active ? undefined : () => setReload(value => value + 1)} />}
        {task && !active && !error && <div role="status" aria-label="Loading plan"><Skeleton variant="card" /></div>}
        {active && <>
          <Card>
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div><h2 className="font-display text-xl font-semibold">{active.title}</h2>
                {active.version && <p className="mt-1 text-sm text-muted-foreground">Plan version {active.version}{!version && active.approved_version ? ` · approved version ${active.approved_version}` : ''}</p>}
                {version && <p className="mt-1 text-sm text-muted-foreground">Latest plan (version {active.latest_version}): {labels[active.status]}</p>}
              </div>
              <Badge variant={!version && active.status === 'approved' ? 'success' : !version && active.status === 'failed' ? 'warning' : 'neutral'}>
                {version ? 'Historical version' : labels[active.status]}
              </Badge>
            </div>
            {active.status === 'not_started' && <div className="mt-4 space-y-3">
              <p className="text-sm text-muted-foreground">Generate a draft from this task’s finalized scope and linked evidence.</p>
              <Button loading={busy} onClick={() => void command('generate')} icon={<ClipboardList />}>Generate AI draft</Button>
            </div>}
            {['queued', 'generating'].includes(active.status) && <p role="status" className="mt-3 text-sm text-muted-foreground">Preparing the draft. You can return to this page when it is ready.</p>}
            {!version && active.generation_error && <ErrorNotice className="mt-3" message={active.generation_error} />}
            {!version && active.retry_available && <Button className="mt-3" variant="secondary" loading={busy} onClick={() => void command('generate')}>Retry generation</Button>}
          </Card>
          {active.context && <PlanEvidence context={active.context} />}
          {active.content && <PlanEditor key={`${task}:${active.version}:${version ?? 'latest'}`} content={active.content}
            context={active.context} readOnly={active.status !== 'draft' || !!version} busy={busy} error={error} onDirtyChange={setHasUnsavedEdits}
            save={(reason, content) => command('edit', reason, content)} approve={reason => command('approve', reason)} />}
          {!!active.history.length && <Card title="Plan history">
            <div className="max-w-xs">
              <Select label="Plan version" disabled={busy} value={version ?? ''} onChange={event => {
                const value = event.target.value;
                setSearch(value ? { task: active.task_id, version: value } : { task: active.task_id });
              }} options={[{ value: '', label: `Latest (version ${active.latest_version})` },
                ...active.history.map(item => ({ value: String(item.version), label: `Version ${item.version} · ${item.action}` }))]} />
            </div>
            <ol className="mt-4 space-y-2 text-sm">
              {active.history.map(item => <li key={item.version} className="rounded-lg border border-border p-3">
                <p className="font-medium">Version {item.version} · {item.action}</p>
                <p>{item.reason}</p>
                <p className="text-xs text-muted-foreground">Consultant #{item.consultant_user_id} · {new Date(item.created_at).toLocaleString()}</p>
              </li>)}
            </ol>
          </Card>}
        </>}
      </div>
    </div>}
    {blocker.state === 'blocked' && <ConfirmDialog open title="Discard unsaved plan edits?"
      description="Your changes will be lost if you leave this plan without saving."
      cancelLabel="Stay" confirmLabel="Discard" loading={busy} onClose={blocker.reset}
      onConfirm={() => { setHasUnsavedEdits(false); blocker.proceed(); }} />}
  </div>;
}

function PlanEvidence({ context }: { context: PlanContext }) {
  return <Card title="Evidence and open questions">
    <div className="space-y-3 text-sm">
      <p><strong>Participants</strong> · {context.participants.length ? context.participants.map(person =>
        [person.display_name || `Employee #${person.id}`, person.role_title, person.department,
          !person.eligible ? 'eligibility needs review' : !person.discovery_consent_recorded ? 'Discovery consent unrecorded' : ''].filter(Boolean).join(' · ')
      ).join(' / ') : 'No participant assigned in the finalized selection.'}</p>
      <p><strong>Workload</strong> · {workload(context.effort.effective_effort)}</p>
      {context.open_clarifications.map(item => <details key={item.id} className="rounded-lg border border-warning/30 bg-warning/10 p-3">
        <summary className="cursor-pointer font-medium">Open clarification #{item.id}</summary>
        <div className="mt-2 space-y-2"><TextList items={item.missing_evidence} /><TextList items={item.why_it_matters} /></div>
      </details>)}
      <details className="rounded-lg border border-border p-3">
        <summary className="cursor-pointer font-medium">Reported process and evidence references</summary>
        <div className="mt-3 space-y-3">
          <p>Cluster revisions {context.cluster_revision_ids.join(', ') || '—'}</p>
          {context.sources.map(source => <section className="space-y-1 rounded-lg border border-border p-3" key={source.id}>
            <h3 className="font-semibold">{source.name}</h3>
            <p className="text-muted-foreground">Source #{source.id} v{source.version} · Discovery conversation #{source.conversation_id}{source.finding_id ? ` · Finding #${source.finding_id}` : ''}</p>
            {source.facts.map(fact => <p key={fact.field}>{words(fact.field)} · {fact.reported_value}
              <span className="text-muted-foreground"> {fact.reference.message_id ? `· message #${fact.reference.message_id}` : `· turn ${fact.reference.turn ?? 'unavailable'}`}</span></p>)}
            {source.effort_observations.map((item, index) => <p key={index}>{item.scope} · {item.effort_type} · {
              [item.duration, item.frequency].map(value => value.min != null ? `${value.min}${value.max && value.max !== value.min ? `–${value.max}` : ''} ${words(value.unit ?? '')}` : 'unquantified').join(' · ')
            }</p>)}
          </section>)}
          {!context.sources.length && <p>No Discovery sources were linked to this task.</p>}
          {context.relationships.map(pair => <p key={pair.source_ids.join(':')}>{words(pair.kind)} · {pair.rationale}</p>)}
          {context.relationship_judgments.map(pair => <p key={pair.source_ids.join(':')}>Consultant judgment · {words(pair.classification)} · {pair.reason}</p>)}
          {Object.values(context.effort.effort_assumptions ?? {}).map((item, index) => <p key={index}>Consultant effort assumption · {item.effort_type} · {item.reason}</p>)}
          <h3 className="font-medium">Saved selection gaps</h3><TextList items={context.gaps} />
        </div>
      </details>
    </div>
  </Card>;
}

function PlanEditor({ content, context, readOnly, busy, error, onDirtyChange, save, approve }: {
  content: PlanContent; context: PlanContext | null; readOnly: boolean; busy: boolean; error: string;
  onDirtyChange: (dirty: boolean) => void;
  save: (reason: string, content: PlanContent) => Promise<boolean>; approve: (reason: string) => Promise<boolean>;
}) {
  const [draft, setDraft] = useState(content);
  const [reason, setReason] = useState('');
  const [approval, setApproval] = useState(false);
  const dirty = JSON.stringify(draft) !== JSON.stringify(content);
  useEffect(() => { onDirtyChange(!readOnly && dirty); }, [readOnly, dirty, onDirtyChange]);

  function questions(sectionIndex: number, list: PlanContent['sections'][number]['questions']) {
    setDraft(previous => ({ ...previous, sections: previous.sections.map((section, i) => i === sectionIndex ? { ...section, questions: list } : section) }));
  }

  return <Card>
    <h2 className="mb-5 font-semibold">Interview plan</h2>
    <form className="space-y-5 text-sm" onSubmit={event => {
      event.preventDefault();
      if (!readOnly && dirty && reason.trim()) void save(reason.trim(), draft);
    }}>
      <fieldset disabled={readOnly || busy} className="space-y-3">
        {([{ key: 'objective', label: 'Objective' }, { key: 'scope', label: 'Scope' }, { key: 'instructions', label: 'Instructions' }] as const).map(({ key, label }) =>
          <Textarea key={key} label={label} className="min-h-0" rows={2} required maxLength={2000} value={draft[key]}
            onChange={event => setDraft({ ...draft, [key]: event.target.value })} />)}
        <div className="max-w-xs">
          <Input label="Duration in minutes" type="number" required min={5} max={120} value={draft.duration_minutes || ''}
            onChange={event => setDraft({ ...draft, duration_minutes: Number(event.target.value) })} />
        </div>
        <div className="grid gap-3 md:grid-cols-2">
          {([{ key: 'focus_areas', label: 'Focus areas' }, { key: 'document_requests', label: 'Documents to request or verify' }] as const).map(({ key, label }) =>
            <PlanLines key={key} label={label} values={draft[key]} onChange={value => setDraft(previous => ({ ...previous, [key]: value }))} />)}
        </div>
      </fieldset>
      <div className="space-y-4">
        {draft.sections.map((section, sectionIndex) => <fieldset key={sectionIndex} aria-label={section.title} disabled={readOnly || busy} className="space-y-3 rounded-xl border border-border p-3 sm:p-4">
          <legend className="px-1 font-semibold">{section.title}</legend>
          {section.questions.map((question, i) => <div key={i} className="space-y-2 rounded-lg bg-muted/40 p-3">
              <Textarea label={`Question ${i + 1}`} className="min-h-0" required rows={2} maxLength={700} value={question.text}
                onChange={event => questions(sectionIndex, section.questions.map((item, index) => index === i ? { ...item, text: event.target.value } : item))} />
            {!!question.source_ids.length && <p className="text-xs text-muted-foreground">Discovery sources {question.source_ids.join(', ')}</p>}
            {readOnly && !!question.clarification_ids.length && <p className="text-xs text-muted-foreground">Clarifications {question.clarification_ids.join(', ')}</p>}
            {!readOnly && <div className="flex flex-wrap gap-2">
              {context?.open_clarifications.map(item => <label className="text-xs" key={item.id}>
                <input type="checkbox" checked={question.clarification_ids.includes(item.id)} onChange={event => {
                  const ids = event.target.checked ? [...question.clarification_ids, item.id] : question.clarification_ids.filter(id => id !== item.id);
                  questions(sectionIndex, section.questions.map((entry, index) => index === i ? { ...entry, clarification_ids: ids } : entry));
                }} /> Addresses clarification #{item.id}
              </label>)}
              {[-1, 1].map(offset => <Button key={offset} type="button" size="sm" variant="ghost"
                disabled={i + offset < 0 || i + offset >= section.questions.length}
                aria-label={`Move question ${i + 1} ${offset < 0 ? 'up' : 'down'}`} icon={offset < 0 ? <ArrowUp /> : <ArrowDown />}
                onClick={() => {
                  const ordered = [...section.questions];
                  [ordered[i], ordered[i + offset]] = [ordered[i + offset], ordered[i]];
                  questions(sectionIndex, ordered);
                }} />)}
              <Button type="button" size="sm" variant="ghost" disabled={section.questions.length === 1}
                onClick={() => questions(sectionIndex, section.questions.filter((_, index) => index !== i))}>Remove question</Button>
            </div>}
          </div>)}
          {!readOnly && <Button type="button" size="sm" variant="secondary" disabled={section.questions.length >= 20}
            onClick={() => questions(sectionIndex, [...section.questions, { text: '', source_ids: [], clarification_ids: [] }])}>Add question</Button>}
        </fieldset>)}
      </div>
      {readOnly ? <p className="flex items-center gap-2 text-muted-foreground"><LockKeyhole className="size-4" /> This version is read-only.</p> :
        <div className="space-y-3 border-t border-border pt-4">
          <Textarea label="Decision reason" className="min-h-0" rows={2} required maxLength={2000} disabled={busy} value={reason}
            onChange={event => setReason(event.target.value)} />
          {error && !approval && <ErrorNotice message={error} />}
          <div className="flex flex-wrap gap-2">
            <Button type="submit" loading={busy} disabled={!dirty || !reason.trim()}>Save new version</Button>
            <Button type="button" variant="secondary" disabled={dirty || busy || !reason.trim()} onClick={() => setApproval(true)}>Approve plan</Button>
          </div>
          <p className="text-xs text-muted-foreground">{dirty ? 'Save your edits before approving.' : 'Enter a reason to approve this version.'}</p>
        </div>}
    </form>
    {approval && <ConfirmDialog open title="Approve interview plan" description="Approve and lock this version as the interview plan?"
      variant="primary" confirmLabel="Confirm approval" loading={busy} onClose={() => { if (!busy) setApproval(false); }}
      onConfirm={() => { void approve(reason.trim()).then(success => { if (success) setApproval(false); }); }}>
      {error && <ErrorNotice className="mt-2" message={error} />}
    </ConfirmDialog>}
  </Card>;
}

function PlanLines({ label, values, onChange }: { label: string; values: string[]; onChange: (values: string[]) => void }) {
  const [text, setText] = useState(values.join('\n'));
  return <Textarea label={label} className="min-h-0" rows={3} value={text} onChange={event => {
      setText(event.target.value);
      onChange(event.target.value.split('\n').map(line => line.trim()).filter(Boolean));
    }} />;
}
