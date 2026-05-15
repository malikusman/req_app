import { useEffect, useState } from 'react';
import { api, type Report } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';

export function CompanyReports() {
  const token = useCompanyToken();
  const [reports, setReports] = useState<Report[]>([]);
  const [generating, setGenerating] = useState(false);
  const [error, setError] = useState('');
  const [shareMsg, setShareMsg] = useState('');

  const load = () => {
    if (!token) return;
    api.companyReports(token).then((d) => setReports(d.reports));
  };

  useEffect(() => {
    load();
    const interval = setInterval(load, 5000);
    return () => clearInterval(interval);
  }, [token]);

  const generate = async () => {
    if (!token) return;
    setError('');
    setGenerating(true);
    try {
      await api.generateReport(token);
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Generate failed');
    } finally {
      setGenerating(false);
    }
  };

  const share = async (id: number) => {
    if (!token) return;
    setShareMsg('');
    try {
      const res = await api.shareReport(token, id, 30);
      setShareMsg(`Share link created (expires ${new Date(res.expires_at).toLocaleDateString()}): ${res.share_url}`);
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Share failed');
    }
  };

  const download = async (id: number) => {
    if (!token) return;
    await api.downloadReport(token, id);
  };

  return (
    <div>
      <h1 style={{ marginTop: 0 }}>Reports</h1>
      <p style={{ color: '#64748b' }}>Generate versioned PDF reports with deltas vs previous versions. Share read-only links with leadership.</p>

      {error && <div className="error">{error}</div>}
      {shareMsg && <div style={{ background: '#d1fae5', color: '#065f46', padding: '0.75rem', borderRadius: 8, marginBottom: '1rem' }}>{shareMsg}</div>}

      <div className="card" style={{ marginBottom: '1.5rem' }}>
        <button type="button" className="btn btn-primary" onClick={generate} disabled={generating}>
          {generating ? 'Generating…' : 'Generate new report'}
        </button>
        <p style={{ color: '#64748b', margin: '0.75rem 0 0', fontSize: '0.9rem' }}>
          Requires readiness score of 100% (or allow_early_report in dev).
        </p>
      </div>

      <div className="card">
        <table>
          <thead>
            <tr>
              <th>Version</th>
              <th>Status</th>
              <th>Generated</th>
              <th>Delta</th>
              <th>Share views</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {reports.map((r) => (
              <tr key={r.id}>
                <td>v{r.version}</td>
                <td>
                  <span className={`badge badge-${r.status === 'ready' ? 'completed' : r.status}`}>{r.status}</span>
                </td>
                <td>{r.generated_at ? new Date(r.generated_at).toLocaleString() : '—'}</td>
                <td>
                  <small>{r.delta_summary || '—'}</small>
                </td>
                <td>
                  {r.access_count > 0 ? (
                    <small>
                      {r.access_count} views
                      {r.last_accessed_at && ` · last ${new Date(r.last_accessed_at).toLocaleString()}`}
                    </small>
                  ) : (
                    '—'
                  )}
                </td>
                <td style={{ whiteSpace: 'nowrap' }}>
                  {r.status === 'ready' && (
                    <>
                      <button type="button" className="btn btn-secondary" onClick={() => download(r.id)}>
                        Download
                      </button>
                      <button type="button" className="btn btn-secondary" style={{ marginLeft: 4 }} onClick={() => share(r.id)}>
                        Share link
                      </button>
                    </>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {reports.length === 0 && <p style={{ color: '#94a3b8' }}>No reports yet.</p>}
      </div>
    </div>
  );
}
