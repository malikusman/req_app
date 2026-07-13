import { useEffect, useState } from 'react';
import { api, type CompanyDocument } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { PageHeader, Card, Input, DataTable, Badge, FileDropzone, EmptyState, Button } from '../../components/ui';

export function CompanyDocuments() {
  const token = useCompanyToken();
  const [documents, setDocuments] = useState<CompanyDocument[]>([]);
  const [department, setDepartment] = useState('');
  const [reviewerVisible, setReviewerVisible] = useState(true);
  const [error, setError] = useState('');
  const [uploading, setUploading] = useState(false);
  const [loading, setLoading] = useState(true);
  const [togglingId, setTogglingId] = useState<number | null>(null);

  const load = () => {
    if (!token) return;
    api
      .companyDocuments(token)
      .then((d) => setDocuments(d.documents))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
  }, [token]);

  const onUpload = async (file: File) => {
    if (!token) return;
    setError('');
    setUploading(true);
    try {
      await api.uploadDocument(token, file, {
        department: department || undefined,
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
        description="Upload SOPs, org charts, or process PDFs to enrich discovery insights. Control what assigned reviewers can see."
      />

      {error && <p className="text-sm text-status-error">{error}</p>}

      <Card title="Upload document">
        <div className="mb-4 flex flex-wrap items-end gap-4">
          <div className="max-w-xs flex-1">
            <Input
              label="Department (optional)"
              value={department}
              onChange={(e) => setDepartment(e.target.value)}
              placeholder="operations"
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
          Supported: PDF, TXT, MD, CSV, DOCX, XLSX, PPTX, and images (max 25MB).
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
        emptyState={<EmptyState title="No documents" description="Upload your first document to enrich insights." />}
      />
    </div>
  );
}
