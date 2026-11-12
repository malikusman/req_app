import { useEffect, useState } from 'react';
import { ArrowLeft, History, RefreshCw } from 'lucide-react';
import { Link, useParams, useSearchParams } from 'react-router-dom';
import { Badge, Button, Card, Skeleton, useToast } from '../../components/ui';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '../../components/shadcn/dialog';
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from '../../components/shadcn/sheet';
import { api } from '../../lib/api';
import { useConsultantToken } from '../../lib/auth';
import type { ReviewCommand, SelectionReview, SelectionRun } from '../../lib/taskSelection';
import type { ParticipantFeedback } from './TaskSelectionDetails';
import { words } from './TaskSelectionEvidence';
import { field } from './TaskSelectionForms';
import { TaskSelectionWorkspace } from './TaskSelectionWorkspace';

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
  const [historyOpen, setHistoryOpen] = useState(false);
  const [reason, setReason] = useState('');
  const [saveError, setSaveError] = useState('');
  const [feedback, setFeedback] = useState<ParticipantFeedback>();
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

  const reviewLabel = current?.status === 'finalized' ? 'Finalized' : readOnly ? 'Historical review' : 'Draft review';

  return <div className="mx-auto max-w-[90rem] space-y-5 sm:space-y-7">
    <header className="rounded-2xl border border-border bg-card px-4 py-5 sm:px-7 sm:py-6">
      <Link className="inline-flex items-center gap-1.5 text-sm font-medium text-primary hover:underline" to={base}>
        <ArrowLeft className="size-4" aria-hidden /> Company overview
      </Link>
      <div className="mt-4 flex flex-wrap items-end justify-between gap-4">
        <div className="space-y-2">
          <div className="flex flex-wrap items-center gap-2.5">
            <h1 className="font-display text-2xl font-semibold tracking-tight sm:text-3xl">Deep Dive Task Selection</h1>
            {current && <Badge variant={current.status === 'finalized' ? 'success' : 'neutral'}>{reviewLabel}</Badge>}
          </div>
          <p className="max-w-prose text-sm text-muted-foreground">Review recommendations, choose tasks for Deep Dive, and assign employees who know the work.</p>
        </div>
        <div className="flex flex-wrap gap-2">
          {run && <Button type="button" size="sm" variant="secondary" icon={<History />} disabled={busy} onClick={() => setHistoryOpen(true)}>Review history</Button>}
          <Button type="button" size="sm" variant="ghost" icon={<RefreshCw />} disabled={busy}
            onClick={() => { setError(''); setReload(value => value + 1); }}>Reload review</Button>
        </div>
      </div>
    </header>

    {error && <p role="alert" className="rounded-xl border border-warning/30 bg-warning/10 p-4 text-sm">{error}</p>}
    {runs && !runs.length && !run && <Card title="No recommendations yet"><p>Run Task Intelligence for this company to start a review.</p></Card>}
    {!current && !error && (!runs || runs.length > 0 || run) && <div role="status" aria-label="Loading task selection" className="space-y-4">
      <div className="grid gap-3 sm:grid-cols-3"><Skeleton variant="card" /><Skeleton variant="card" /><Skeleton variant="card" /></div>
      <Skeleton variant="card" />
    </div>}
    {current && <TaskSelectionWorkspace key={`${current.run.id}:${version ?? 'latest'}`} review={current} readOnly={readOnly}
      busy={busy} feedback={feedback} save={save} onHistory={() => setHistoryOpen(true)} />}

    {historyOpen && run && <Sheet open onOpenChange={setHistoryOpen}>
      <SheetContent aria-label="Review history" className="w-full overflow-y-auto sm:max-w-lg">
        <SheetHeader className="mb-5 pr-8 text-left">
          <SheetTitle>Review history</SheetTitle>
          <SheetDescription>Inspect past recommendations and decisions. Historical revisions are read-only.</SheetDescription>
        </SheetHeader>
        <div className="grid gap-3 rounded-xl border border-border bg-card p-4 text-sm sm:grid-cols-2">
          <label className="space-y-1 font-medium">Recommendation set
            <select className={`${field} block w-full`} value={run} disabled={busy} onChange={event => {
              setError(''); setSearch({ run: event.target.value });
            }}>
              {!runs?.some(item => String(item.id) === run) && <option value={run}>Set #{run}</option>}
              {runs?.map(item => <option key={item.id} value={item.id}>Version {item.version}</option>)}
            </select>
          </label>
          {current && <label className="space-y-1 font-medium">Review revision
            <select className={`${field} block w-full`} value={version ?? ''} disabled={busy} onChange={event => {
              setError(''); setSearch(event.target.value ? { run, version: event.target.value } : { run });
            }}>
              <option value="">Latest (v{current.latest_version})</option><option value="0">Initial proposals</option>
              {current.history.map(item => <option key={item.version} value={item.version}>v{item.version} · {words(item.action)}</option>)}
            </select>
          </label>}
          {!!runList?.before && <Button variant="secondary" size="sm" onClick={loadOlderRuns}>Load older sets</Button>}
        </div>
        {current && <ol className="mt-5 space-y-4 border-l border-border pl-4 text-sm">
          {current.history.filter(item => item.version <= current.version).map(item => <li key={item.version}>
            <p className="font-semibold capitalize">{words(item.action)}</p>
            <p className="text-xs text-muted-foreground">v{item.version} · consultant #{item.consultant_user_id} · {new Date(item.created_at).toLocaleString()}</p>
            <p className="mt-1 break-words">{item.reason}</p>
          </li>)}
          {!current.version && <li className="text-muted-foreground">No consultant decisions yet.</li>}
        </ol>}
      </SheetContent>
    </Sheet>}
    {pending && <Dialog open onOpenChange={open => { if (!open && !busy) setPending(undefined); }}>
      <DialogContent aria-label={actionLabels[pending.action]} className="rounded-xl">
      <DialogHeader>
        <DialogTitle>{actionLabels[pending.action]}</DialogTitle>
        <DialogDescription>{pending.action === 'finalize'
          ? `Approve ${current?.snapshot.selected_order.length} selected task(s) for Deep Dive planning? Finalizing locks this review and keeps any unresolved gaps with the selection.`
          : 'Record why you made this decision so it can be reviewed later.'}</DialogDescription>
      </DialogHeader>
      <form className="space-y-4 text-sm" onSubmit={event => {
        event.preventDefault();
        if (reason.trim()) void persist(pending, reason.trim());
        else setSaveError('Enter a reason for this decision.');
      }}>
        <label className="block font-medium">Reason
          <textarea autoFocus className={`${field} mt-1 block w-full`} rows={3} maxLength={2000} required value={reason} onChange={event => setReason(event.target.value)} />
        </label>
        {saveError && <p role="alert" className="text-destructive">{saveError}</p>}
        <div className="flex justify-end gap-2">
          <Button type="button" variant="secondary" disabled={busy} onClick={() => setPending(undefined)}>Cancel</Button>
          <Button type="submit" loading={busy}>{pending.action === 'finalize' ? 'Confirm finalization' : 'Save decision'}</Button>
        </div>
      </form>
      </DialogContent>
    </Dialog>}
  </div>;
}
