import { useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api, type CompanyDocument } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { PageHeader, Card, Input, DataTable, Badge, FileDropzone, EmptyState, Button } from '../../components/ui';
import { useToast } from '../../components/ui/ToastProvider';

export function CompanyDocuments() {
  const token = useCompanyToken();
  const navigate = useNavigate();
  const { toast } = useToast();
  const [documents, setDocuments] = useState<CompanyDocument[]>([]);
  const [department, setDepartment] = useState('');
  const [reviewerVisible, setReviewerVisible] = useState(true);
  const [error, setError] = useState('');
  const [loadError, setLoadError] = useState('');
  const [uploading, setUploading] = useState(false);
  const [loading, setLoading] = useState(true);
  const [togglingId, setTogglingId] = useState<number | null>(null);
  const celebratedReady = useRef(false);

  const load = () => {
    if (!token) return;
    api
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
              title: 'First document ready',
              description: 'Text extracted — check Signals next, or upload more for coverage.',
            });
          }
        }
      })
      .catch(() => setLoadError('Could not load documents.'))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
  }, [token]);

  useEffect(() => {
    if (!token) return;
    const processing = documents.some((d) => d.status === 'processing' || d.status === 'pending');
    if (!processing) return;
    const id = window.setInterval(load, 3000);
    return () => window.clearInterval(id);
  }, [token, documents]);

  const onUpload = async (file: File) => {
    if (!token) return;
    setError('');
    const lower = file.name.toLowerCase();
    if (/\.(pptx|jpg|jpeg|png|webp)$/i.test(lower)) {
      setError(
        'Images and PowerPoint files often have little extractable text. Prefer PDF, DOCX, XLSX, CSV, or Markdown for readiness and signals.'
      );
    }
    if (!department.trim()) {
      setError((prev) =>
        prev
          ? `${prev} Tip: tag a department so document coverage counts toward readiness.`
          : 'Tip: tag a department so document coverage counts toward readiness.'
      );
    }
    setUploading(true);
    try {
      await api.uploadDocument(token, file, {
        department: department.trim() || undefined,
        reviewer_visible: reviewerVisible,
      });
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Upload failed');
    } finally {
      setUploading(false);
    }
  };

  const toggleReviewerVisible = async (doc: CompanyDocument) => {
    if (!token) return;
    setError('');
    setTogglingId(doc.id);
    const next = doc.reviewer_visible === false;
    try {
      const { document } = await api.updateCompanyDocument(token, doc.id, { reviewer_visible: next });
      setDocuments((prev) => prev.map((d) => (d.id === doc.id ? document : d)));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Update failed');
    } finally {
      setTogglingId(null);
    }
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="Documents"
        description="Upload SOPs, policies, and finance exports to build a discovery baseline. Tag departments for readiness coverage. Control what assigned reviewers can see."
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
              checked={reviewerVisible}
              onChange={(e) => setReviewerVisible(e.target.checked)}
            />
            Visible to reviewers
          </label>
        </div>
        <FileDropzone accept=".pdf,.txt,.md,.csv,.docx,.xlsx,.pptx,.jpg,.jpeg,.png,.webp" onFile={onUpload} />
        {uploading && <p className="mt-2 text-sm text-text-secondary">Uploading…</p>}
        <p className="mt-2 text-xs text-text-secondary">
          Best: PDF, DOCX, XLSX, CSV, Markdown. PPTX and images are accepted but often fail text extraction (min 40 characters required for Ready).
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
              <Badge variant={d.status === 'ready' ? 'success' : d.status === 'failed' ? 'error' : 'info'}>
                {d.status}
              </Badge>
            ),
          },
          {
            key: 'reviewer_visible',
            header: 'Reviewers',
            render: (d) => (
              <div className="flex items-center gap-2">
                <Badge variant={d.reviewer_visible === false ? 'warning' : 'success'}>
                  {d.reviewer_visible === false ? 'Hidden' : 'Visible'}
                </Badge>
                <Button
                  size="sm"
                  variant="ghost"
                  loading={togglingId === d.id}
                  onClick={() => toggleReviewerVisible(d)}
                >
                  {d.reviewer_visible === false ? 'Show' : 'Hide'}
                </Button>
              </div>
            ),
          },
          {
            key: 'preview',
            header: 'Preview',
            render: (d) => (
              <span className="text-xs text-text-secondary">
                {d.insights_preview?.summary || (d.status === 'processing' ? 'Processing…' : '—')}
              </span>
            ),
          },
        ]}
        rows={documents as CompanyDocument[]}
        emptyState={
          <EmptyState
            title="No documents yet"
            description="Drop your first SOP, policy, or export above to start a document baseline — no employees required."
            action={{ label: 'Invite employees later', onClick: () => navigate('/company/employees') }}
          />
        }
      />
    </div>
  );
}
