import { useEffect, useState } from 'react';
import { api, type CompanyDocument } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { PageHeader, Card, Input, DataTable, Badge, FileDropzone, EmptyState } from '../../components/ui';

export function CompanyDocuments() {
  const token = useCompanyToken();
  const [documents, setDocuments] = useState<CompanyDocument[]>([]);
  const [department, setDepartment] = useState('');
  const [error, setError] = useState('');
  const [uploading, setUploading] = useState(false);
  const [loading, setLoading] = useState(true);

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
      await api.uploadDocument(token, file, department || undefined);
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Upload failed');
    } finally {
      setUploading(false);
    }
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="Documents"
        description="Upload SOPs, org charts, or process PDFs to enrich discovery insights."
      />

      {error && <p className="text-sm text-status-error">{error}</p>}

      <Card title="Upload document">
        <div className="mb-4 max-w-xs">
          <Input
            label="Department (optional)"
            value={department}
            onChange={(e) => setDepartment(e.target.value)}
            placeholder="operations"
          />
        </div>
        <FileDropzone accept=".pdf,.txt,.md,.csv" onFile={onUpload} />
        {uploading && <p className="mt-2 text-sm text-text-secondary">Uploading…</p>}
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
