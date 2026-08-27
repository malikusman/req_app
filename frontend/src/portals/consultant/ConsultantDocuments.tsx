import { useEffect, useState } from 'react';
import { useParams } from 'react-router-dom';
import { Download, FileText } from 'lucide-react';
import { api, type CompanyDocument } from '../../lib/api';
import { useConsultantToken } from '../../lib/auth';
import { PageHeader, Card, DataTable, Badge, EmptyState, Skeleton, Button } from '../../components/ui';
import { Sheet, SheetContent, SheetHeader, SheetTitle } from '@/components/shadcn/sheet';
import { useMediaQuery } from '../../lib/useMediaQuery';

function formatBytes(n: number) {
  if (!n) return '—';
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / (1024 * 1024)).toFixed(1)} MB`;
}

export function ConsultantDocuments() {
  const { companyId } = useParams();
  const token = useConsultantToken();
  const isNarrow = useMediaQuery('(max-width: 1023px)');
  const [documents, setDocuments] = useState<CompanyDocument[]>([]);
  const [selected, setSelected] = useState<CompanyDocument | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [downloadingId, setDownloadingId] = useState<number | null>(null);

  useEffect(() => {
    if (!token || !companyId) return;
    setLoading(true);
    api
      .consultantDocuments(token, Number(companyId))
      .then((d) => setDocuments(d.documents))
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load documents'))
      .finally(() => setLoading(false));
  }, [token, companyId]);

  const onDownload = async (doc: CompanyDocument) => {
    if (!token || !companyId) return;
    setDownloadingId(doc.id);
    setError('');
    try {
      await api.downloadConsultantDocument(token, Number(companyId), doc.id, doc.filename);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Download failed');
    } finally {
      setDownloadingId(null);
    }
  };

  if (loading) {
    return (
      <div className="space-y-4">
        <Skeleton variant="text" />
        <Skeleton variant="card" />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="Company documents"
        description="Internal docs shared with consultants for evidence and context."
        breadcrumbs={[
          { label: 'Dashboard', href: '/consultant/dashboard' },
          { label: 'Company', href: `/consultant/companies/${companyId}` },
          { label: 'Documents' },
        ]}
      />

      {error && <p className="text-sm text-status-error">{error}</p>}

      <div className="grid gap-4 lg:grid-cols-[1fr_340px]">
        <DataTable
          onRowClick={setSelected}
          columns={[
            {
              key: 'filename',
              header: 'File',
              render: (d) => (
                <span className="text-sm font-medium text-text-primary">{d.filename}</span>
              ),
            },
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
              key: 'size',
              header: 'Size',
              render: (d) => <span className="text-xs text-text-secondary">{formatBytes(d.byte_size)}</span>,
            },
            {
              key: 'actions',
              header: '',
              render: (d) => (
                <Button
                  size="sm"
                  variant="ghost"
                  icon={<Download className="h-3.5 w-3.5" />}
                  loading={downloadingId === d.id}
                  onClick={(e) => {
                    e.stopPropagation();
                    onDownload(d);
                  }}
                >
                  Download
                </Button>
              ),
            },
          ]}
          rows={documents}
          emptyState={
            <EmptyState
              title="No shared documents"
              description="When the company uploads documents marked visible to consultants, they appear here."
            />
          }
        />

        <Card className="hidden lg:block" title="Document detail">
          {!selected ? (
            <p className="text-sm text-text-secondary">Select a document to see AI-extracted context.</p>
          ) : (
            <div className="space-y-3 text-sm">
              <div className="flex items-start gap-2">
                <FileText className="mt-0.5 h-4 w-4 shrink-0 text-text-secondary" />
                <div>
                  <div className="font-medium">{selected.filename}</div>
                  <div className="text-xs text-text-secondary">
                    {selected.document_type || 'document'}
                    {selected.department ? ` · ${selected.department}` : ''}
                  </div>
                </div>
              </div>
              <div>
                <div className="mb-1 text-xs uppercase tracking-wide text-text-secondary">Summary</div>
                <p className="m-0 text-sm text-text-primary">
                  {selected.insights_preview?.summary || 'No summary yet — document may still be processing.'}
                </p>
              </div>
              {!!selected.insights_preview?.workflows?.length && (
                <div>
                  <div className="mb-1 text-xs uppercase tracking-wide text-text-secondary">Workflows</div>
                  <ul className="m-0 list-disc space-y-1 pl-4 text-xs">
                    {selected.insights_preview.workflows.map((w) => (
                      <li key={w}>{w}</li>
                    ))}
                  </ul>
                </div>
              )}
              {!!selected.insights_preview?.friction_points?.length && (
                <div>
                  <div className="mb-1 text-xs uppercase tracking-wide text-text-secondary">Friction</div>
                  <ul className="m-0 list-disc space-y-1 pl-4 text-xs">
                    {selected.insights_preview.friction_points.map((w) => (
                      <li key={w}>{w}</li>
                    ))}
                  </ul>
                </div>
              )}
              {typeof selected.insights_preview?.chunk_count === 'number' && (
                <p className="m-0 text-xs text-text-secondary">
                  Indexed chunks: {selected.insights_preview.chunk_count}
                </p>
              )}
              <Button
                size="sm"
                variant="secondary"
                icon={<Download className="h-3.5 w-3.5" />}
                loading={downloadingId === selected.id}
                onClick={() => onDownload(selected)}
              >
                Download file
              </Button>
            </div>
          )}
        </Card>

        <Sheet open={Boolean(selected) && isNarrow} onOpenChange={(open) => !open && setSelected(null)}>
          <SheetContent side="bottom" className="max-h-[85dvh] overflow-y-auto">
            <SheetHeader>
              <SheetTitle>Document detail</SheetTitle>
            </SheetHeader>
            {selected ? (
              <div className="mt-4 space-y-3 text-sm">
                <div className="font-medium">{selected.filename}</div>
                <p className="m-0 text-sm text-text-primary">
                  {selected.insights_preview?.summary || 'No summary yet — document may still be processing.'}
                </p>
                <Button
                  size="sm"
                  variant="secondary"
                  icon={<Download className="h-3.5 w-3.5" />}
                  loading={downloadingId === selected.id}
                  onClick={() => onDownload(selected)}
                >
                  Download file
                </Button>
              </div>
            ) : null}
          </SheetContent>
        </Sheet>
      </div>
    </div>
  );
}
