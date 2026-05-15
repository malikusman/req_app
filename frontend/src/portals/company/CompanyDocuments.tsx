import { useEffect, useState } from 'react';
import { api, type CompanyDocument } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';

export function CompanyDocuments() {
  const token = useCompanyToken();
  const [documents, setDocuments] = useState<CompanyDocument[]>([]);
  const [department, setDepartment] = useState('');
  const [error, setError] = useState('');
  const [uploading, setUploading] = useState(false);

  const load = () => {
    if (!token) return;
    api.companyDocuments(token).then((d) => setDocuments(d.documents));
  };

  useEffect(() => {
    load();
  }, [token]);

  const onUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file || !token) return;
    setError('');
    setUploading(true);
    try {
      await api.uploadDocument(token, file, department || undefined);
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Upload failed');
    } finally {
      setUploading(false);
      e.target.value = '';
    }
  };

  return (
    <div>
      <h1 style={{ marginTop: 0 }}>Documents</h1>
      <p style={{ color: '#64748b' }}>
        Upload SOPs, org charts, or process PDFs. We parse, chunk, and embed them to enrich discovery insights before interviews complete.
      </p>

      {error && <div className="error">{error}</div>}

      <div className="card" style={{ marginBottom: '1.5rem' }}>
        <h3 style={{ marginTop: 0 }}>Upload document</h3>
        <div className="form-group">
          <label>Department (optional)</label>
          <input value={department} onChange={(e) => setDepartment(e.target.value)} placeholder="operations" />
        </div>
        <div className="form-group">
          <label>PDF or text file</label>
          <input type="file" accept=".pdf,.txt,.md,.csv" onChange={onUpload} disabled={uploading} />
        </div>
        {uploading && <p style={{ color: '#64748b' }}>Uploading…</p>}
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Library</h3>
        <table>
          <thead>
            <tr>
              <th>File</th>
              <th>Department</th>
              <th>Status</th>
              <th>Preview</th>
            </tr>
          </thead>
          <tbody>
            {documents.map((d) => (
              <tr key={d.id}>
                <td>{d.filename}</td>
                <td>{d.department || '—'}</td>
                <td>
                  <span className={`badge badge-${d.status === 'ready' ? 'completed' : d.status}`}>{d.status}</span>
                </td>
                <td>
                  <small>{d.insights_preview?.summary || (d.status === 'processing' ? 'Processing…' : '—')}</small>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {documents.length === 0 && <p style={{ color: '#64748b' }}>No documents uploaded yet.</p>}
      </div>
    </div>
  );
}
