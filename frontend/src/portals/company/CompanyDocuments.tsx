import { useEffect, useRef, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { Download, HelpCircle, Pencil, Trash2, Upload } from 'lucide-react';
import { api, type CompanyDocument, type DocumentAnalysisRun } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { PageHeader, Card, Input, DataTable, Badge, FileDropzone, EmptyState, Button } from '../../components/ui';
import { useToast } from '../../components/ui/ToastProvider';

export function CompanyDocuments() {
  const token = useCompanyToken();
  const navigate = useNavigate();
  const { toast } = useToast();
  const [documents, setDocuments] = useState<CompanyDocument[]>([]);
  const [department, setDepartment] = useState('');
  const [consultantVisible, setConsultantVisible] = useState(true);
  const [error, setError] = useState('');
  const [loadError, setLoadError] = useState('');
  const [uploading, setUploading] = useState(false);
  const [batch, setBatch] = useState<{ done: number; total: number } | null>(null);
  const [loading, setLoading] = useState(true);
  const [togglingId, setTogglingId] = useState<number | null>(null);
  const [actingId, setActingId] = useState<number | null>(null);
  const [analyzing, setAnalyzing] = useState(false);
  const [awaitingCount, setAwaitingCount] = useState(0);
  const [profileStale, setProfileStale] = useState(false);
  const [activeRun, setActiveRun] = useState<DocumentAnalysisRun | null>(null);
  const [latestRun, setLatestRun] = useState<DocumentAnalysisRun | null>(null);
  const [intelUpdating, setIntelUpdating] = useState(false);
  const celebratedReady = useRef(false);
  const celebratedRunId = useRef<number | null>(null);
  const prevActiveRunId = useRef<number | null>(null);
  const replaceInputRef = useRef<HTMLInputElement>(null);
  const replaceTargetId = useRef<number | null>(null);
  const uploadInputRef = useRef<HTMLInputElement>(null);

  const loadDocs = () => {
    if (!token) return Promise.resolve();
    return api
      .companyDocuments(token)
      .then((d) => {
        setDocuments(d.documents);
        setLoadError('');
        const readyCount = d.documents.filter((doc) => doc.status === 'ready').length;
        if (readyCount > 0 && !celebratedReady.current) {
          celebratedReady.current = true;
          if (readyCount === 1) {
            toast({
              variant: 'success',
              title: 'First document analyzed',
              description: 'Open Knowledge to review the knowledge base and any clarification questions.',
            });
          }
        }
      })
      .catch(() => setLoadError('Could not load documents.'));
  };

  const loadRuns = () => {
    if (!token) return Promise.resolve();
    return api
      .documentAnalysisRuns(token)
      .then((d) => {
        setAwaitingCount(d.awaiting_analysis_count);
        setProfileStale(d.profile_stale);
        const hadActive = prevActiveRunId.current != null;
        setActiveRun(d.active_run);
        prevActiveRunId.current = d.active_run?.id ?? null;
        setLatestRun(d.runs[0] || null);

        const finished = d.runs[0];
        const justFinished =
          hadActive &&
          !d.active_run &&
          finished &&
          ['completed', 'completed_with_errors'].includes(finished.status) &&
          celebratedRunId.current !== finished.id;

        if (justFinished && finished) {
          celebratedRunId.current = finished.id;
          setIntelUpdating(true);
          toast({
            variant: 'success',
            title: 'Analysis complete',
            description: 'Intelligence is refreshing from your documents (signals, patterns, readiness).',
          });
          window.setTimeout(() => setIntelUpdating(false), 12_000);
        }
      })
      .catch(() => undefined);
  };

  const load = () => {
    if (!token) return;
    Promise.all([loadDocs(), loadRuns()]).finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
  }, [token]);

  useEffect(() => {
    if (!token) return;
    const busy =
      Boolean(activeRun) ||
      documents.some((d) => d.status === 'processing' || d.status === 'pending');
    if (!busy) return;
    const id = window.setInterval(load, 3000);
    return () => window.clearInterval(id);
  }, [token, documents, activeRun]);

  const onUploadMany = async (files: File[]) => {
    if (!token || files.length === 0) return;
    setError('');

    // One-time, batch-level hints (not per file).
    const hints: string[] = [];
    if (files.some((f) => /\.(pptx|jpg|jpeg|png|webp)$/i.test(f.name.toLowerCase()))) {
      hints.push(
        'Images and PowerPoint files often have little extractable text. Prefer PDF, DOCX, XLSX, CSV, or Markdown.'
      );
    }
    if (!department.trim()) {
      hints.push('Tip: tag a department so document coverage counts toward readiness.');
    }
    if (hints.length) setError(hints.join(' '));

    setUploading(true);
    setBatch({ done: 0, total: files.length });
    let ok = 0;
    const failed: string[] = [];
    for (const file of files) {
      try {
        await api.uploadDocument(token, file, {
          department: department.trim() || undefined,
          consultant_visible: consultantVisible,
        });
        ok += 1;
      } catch {
        failed.push(file.name);
      }
      setBatch({ done: ok + failed.length, total: files.length });
    }
    setBatch(null);
    setUploading(false);

    if (ok > 0) {
      toast({
        variant: failed.length ? 'warning' : 'success',
        title: failed.length
          ? `Uploaded ${ok} of ${files.length}`
          : ok === 1
            ? 'Uploaded'
            : `Uploaded ${ok} documents`,
        description: failed.length
          ? `Couldn't upload: ${failed.join(', ')}`
          : 'Stored. Click Analyze when ready.',
      });
      load();
    } else {
      setError(`Upload failed for ${failed.join(', ')}`);
    }
  };

  const startAnalysis = async (runKind?: string) => {
    if (!token) return;
    setError('');
    setAnalyzing(true);
    try {
      const { run } = await api.startDocumentAnalysis(token, runKind ? { run_kind: runKind } : {});
      setActiveRun(run);
      toast({
        variant: 'success',
        title: 'Analysis started',
        description: `Run #${run.id} (${run.run_kind}) is processing your documents.`,
      });
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not start analysis');
    } finally {
      setAnalyzing(false);
    }
  };

  const toggleConsultantVisible = async (doc: CompanyDocument) => {
    if (!token) return;
    setError('');
    setTogglingId(doc.id);
    const next = doc.consultant_visible === false;
    try {
      const { document } = await api.updateCompanyDocument(token, doc.id, { consultant_visible: next });
      setDocuments((prev) => prev.map((d) => (d.id === doc.id ? document : d)));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Update failed');
    } finally {
      setTogglingId(null);
    }
  };

  const requestReplace = (doc: CompanyDocument) => {
    replaceTargetId.current = doc.id;
    replaceInputRef.current?.click();
  };

  const onReplaceFile = async (file: File | null) => {
    if (!token || !file || replaceTargetId.current == null) return;
    const id = replaceTargetId.current;
    replaceTargetId.current = null;
    setActingId(id);
    setError('');
    try {
      await api.replaceCompanyDocument(token, id, file);
      toast({
        variant: 'success',
        title: 'Document replaced',
        description: 'File queued for analysis — click Update analysis when ready.',
      });
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Replace failed');
    } finally {
      setActingId(null);
      if (replaceInputRef.current) replaceInputRef.current.value = '';
    }
  };

  const onDelete = async (doc: CompanyDocument) => {
    if (!token) return;
    if (!window.confirm(`Remove ${doc.filename}? Related knowledge entries will be orphaned or superseded.`)) {
      return;
    }
    setActingId(doc.id);
    setError('');
    try {
      await api.deleteCompanyDocument(token, doc.id);
      toast({ variant: 'success', title: 'Document removed', description: 'Intelligence will refresh shortly.' });
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Delete failed');
    } finally {
      setActingId(null);
    }
  };

  const onDownload = async (doc: CompanyDocument) => {
    if (!token) return;
    setActingId(doc.id);
    setError('');
    try {
      await api.downloadCompanyDocument(token, doc.id, doc.filename);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Download failed');
    } finally {
      setActingId(null);
    }
  };

  const hasPriorAnalysis = Boolean(
    latestRun && ['completed', 'completed_with_errors'].includes(latestRun.status)
  );
  const analyzeLabel = !hasPriorAnalysis
    ? 'Analyze documents'
    : awaitingCount > 0
      ? `Update analysis (${awaitingCount})`
      : profileStale
        ? 'Refresh grounding'
        : 'Update analysis';
  const canAnalyze =
    !activeRun &&
    !analyzing &&
    (awaitingCount > 0 || profileStale || (!hasPriorAnalysis && documents.length > 0));

  return (
    <div className="space-y-6">
      <input
        ref={replaceInputRef}
        type="file"
        className="hidden"
        accept=".pdf,.txt,.md,.csv,.docx,.xlsx,.pptx,.jpg,.jpeg,.png,.webp"
        onChange={(e) => void onReplaceFile(e.target.files?.[0] || null)}
      />
      <input
        ref={uploadInputRef}
        type="file"
        multiple
        className="hidden"
        accept=".pdf,.txt,.md,.csv,.docx,.xlsx,.pptx,.jpg,.jpeg,.png,.webp"
        onChange={(e) => {
          const files = Array.from(e.target.files ?? []);
          if (files.length) void onUploadMany(files);
          if (uploadInputRef.current) uploadInputRef.current.value = '';
        }}
      />

      <PageHeader
        title="Documents"
        description="Upload SOPs, policies, and finance exports to build a baseline."
        actions={
          <div className="flex flex-wrap gap-2">
            <Link to="/company/discovery-questions">
              <Button variant="secondary" size="sm" icon={<HelpCircle className="h-4 w-4" />}>
                Questions asked
              </Button>
            </Link>
            <Link to="/company/knowledge">
              <Button variant="secondary" size="sm">
                Knowledge
              </Button>
            </Link>
            <Button
              variant="secondary"
              size="sm"
              loading={analyzing}
              disabled={!canAnalyze}
              onClick={() => startAnalysis()}
            >
              {activeRun ? `Analyzing… (${activeRun.phase || activeRun.status})` : analyzeLabel}
            </Button>
            <Button
              size="sm"
              loading={uploading}
              icon={<Upload className="h-4 w-4" />}
              onClick={() => uploadInputRef.current?.click()}
            >
              {batch ? `Uploading ${batch.done}/${batch.total}…` : 'Upload files'}
            </Button>
          </div>
        }
      />

      {error && <p className="text-sm text-status-error">{error}</p>}

      {loadError && (
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-button border border-status-error/30 bg-status-errorBg px-4 py-3 text-sm text-status-error">
          <span>{loadError}</span>
          <Button size="sm" variant="secondary" onClick={load}>
            Retry
          </Button>
        </div>
      )}

      <Card title="How analysis works">
        <p className="m-0 text-sm text-text-secondary">
          Upload as many relevant documents as you can. Files stay as <strong>uploaded</strong> until you click{' '}
          <strong>Analyze documents</strong>. Analysis extracts text, builds a knowledge base, and may ask
          clarification questions when the documents leave gaps. After analysis finishes, intelligence
          (signals, patterns, readiness) refreshes automatically.
        </p>
        {activeRun && (
          <p className="mt-3 text-sm text-text-primary">
            Run #{activeRun.id} · {activeRun.run_kind} · phase{' '}
            <Badge variant="info">{activeRun.phase || activeRun.status}</Badge>
          </p>
        )}
        {intelUpdating && !activeRun && (
          <p className="mt-3 text-sm text-text-primary">
            <Badge variant="info">Intelligence updating…</Badge> Refreshing signals and readiness from your
            documents.
          </p>
        )}
        {!activeRun && latestRun && (
          <p className="mt-3 text-sm text-text-secondary">
            Last run #{latestRun.id}: {latestRun.status}
            {latestRun.error_message ? ` — ${latestRun.error_message}` : ''}
          </p>
        )}
        {awaitingCount > 0 && !activeRun && (
          <div className="mt-3 flex flex-wrap items-center justify-between gap-3 rounded-button border border-border bg-surface-muted px-4 py-3 text-sm">
            <span>
              {awaitingCount} document{awaitingCount === 1 ? '' : 's'} not analyzed yet
            </span>
            <Button size="sm" loading={analyzing} onClick={() => startAnalysis('incremental_docs')}>
              Update analysis
            </Button>
          </div>
        )}
        {profileStale && !activeRun && (
          <div className="mt-3 flex flex-wrap items-center justify-between gap-3 rounded-button border border-border bg-surface-muted px-4 py-3 text-sm">
            <span>Company profile updated — refresh analysis grounding</span>
            <Button
              size="sm"
              variant="secondary"
              loading={analyzing}
              onClick={() => startAnalysis('profile_reground')}
            >
              Refresh grounding
            </Button>
          </div>
        )}
        {hasPriorAnalysis && !activeRun && (
          <div className="mt-3">
            <Button
              size="sm"
              variant="ghost"
              loading={analyzing}
              onClick={() => {
                if (
                  window.confirm(
                    'Rebuild the knowledge base from all documents? Open clarification questions will be marked stale; answered questions are kept.'
                  )
                ) {
                  startAnalysis('full');
                }
              }}
            >
              Rebuild knowledge base…
            </Button>
          </div>
        )}
      </Card>

      <Card title="Upload document">
        <div className="mb-4 flex flex-wrap items-end gap-4">
          <div className="max-w-xs flex-1">
            <Input
              label="Department (recommended)"
              value={department}
              onChange={(e) => setDepartment(e.target.value)}
              placeholder="finance, quality, operations…"
            />
          </div>
          <label className="flex cursor-pointer items-center gap-2 pb-2 text-sm text-text-primary">
            <input
              type="checkbox"
              className="h-4 w-4 rounded border-border"
              checked={consultantVisible}
              onChange={(e) => setConsultantVisible(e.target.checked)}
            />
            Visible to consultants
          </label>
        </div>
        <FileDropzone
          multiple
          accept=".pdf,.txt,.md,.csv,.docx,.xlsx,.pptx,.jpg,.jpeg,.png,.webp"
          onFiles={onUploadMany}
        />
        {batch && (
          <p className="mt-2 text-sm text-text-secondary">Uploading {batch.done} of {batch.total}…</p>
        )}
        {uploading && <p className="mt-2 text-sm text-text-secondary">Uploading…</p>}
        <p className="mt-2 text-xs text-text-secondary">
          Best: PDF, DOCX, XLSX, CSV, Markdown. Analysis does not start automatically on upload.
        </p>
      </Card>

      <DataTable
        loading={loading}
        columns={[
          { key: 'filename', header: 'File' },
          { key: 'department', header: 'Department', render: (d) => d.department || '—' },
          {
            key: 'status',
            header: 'Status',
            render: (d) => (
              <Badge
                variant={
                  d.status === 'ready'
                    ? 'success'
                    : d.status === 'failed'
                      ? 'error'
                      : d.status === 'uploaded'
                        ? 'warning'
                        : 'info'
                }
              >
                {d.status}
              </Badge>
            ),
          },
          {
            key: 'consultant_visible',
            header: 'Consultants',
            render: (d) => (
              <div className="flex items-center gap-2">
                <Badge variant={d.consultant_visible === false ? 'warning' : 'success'}>
                  {d.consultant_visible === false ? 'Hidden' : 'Visible'}
                </Badge>
                <Button
                  size="sm"
                  variant="ghost"
                  loading={togglingId === d.id}
                  onClick={() => toggleConsultantVisible(d)}
                >
                  {d.consultant_visible === false ? 'Show' : 'Hide'}
                </Button>
              </div>
            ),
          },
          {
            key: 'preview',
            header: 'Preview',
            render: (d) => (
              <span className="text-xs text-text-secondary">
                {d.insights_preview?.summary ||
                  (d.status === 'failed' && d.processing_error
                    ? d.processing_error
                    : d.status === 'uploaded'
                      ? 'Waiting for Analyze'
                      : d.status === 'processing'
                        ? 'Processing…'
                        : '—')}
              </span>
            ),
          },
          {
            key: 'updated_at',
            header: 'Updated',
            render: (d) => (
              <span className="whitespace-nowrap text-xs text-text-secondary">
                {d.updated_at ? new Date(d.updated_at).toLocaleString() : '—'}
              </span>
            ),
          },
          {
            key: 'actions',
            header: '',
            render: (d) =>
              d.status === 'failed' && d.processing_error === 'purged' ? null : (
                <div className="flex flex-wrap gap-1">
                  <Button
                    size="sm"
                    variant="secondary"
                    loading={actingId === d.id}
                    disabled={d.status === 'failed'}
                    icon={<Download className="h-3.5 w-3.5" />}
                    onClick={() => void onDownload(d)}
                    aria-label="Download"
                  >
                    Download
                  </Button>
                  <Button
                    size="sm"
                    variant="secondary"
                    loading={actingId === d.id}
                    icon={<Pencil className="h-3.5 w-3.5" />}
                    onClick={() => requestReplace(d)}
                    aria-label="Replace"
                  >
                    Replace
                  </Button>
                  <Button
                    size="sm"
                    variant="danger"
                    loading={actingId === d.id}
                    icon={<Trash2 className="h-3.5 w-3.5" />}
                    onClick={() => onDelete(d)}
                    aria-label="Delete"
                  >
                    Delete
                  </Button>
                </div>
              ),
          },
        ]}
        rows={documents as CompanyDocument[]}
        emptyState={
          <EmptyState
            title="No documents yet"
            description="Upload a few SOPs, policies, or finance exports to start a baseline."
            action={{ label: 'Upload a document', onClick: () => uploadInputRef.current?.click() }}
            secondaryAction={{ label: 'Invite your team later', onClick: () => navigate('/company/employees') }}
          />
        }
      />
    </div>
  );
}
