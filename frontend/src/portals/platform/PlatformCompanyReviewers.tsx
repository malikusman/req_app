import { useEffect, useState } from 'react';
import { api, type ReviewerAssignment, type ReviewerUser } from '../../lib/api';
import { usePlatformToken } from '../../lib/auth';

type Props = { companyId: number; companyName: string; onClose: () => void };

export function PlatformCompanyReviewers({ companyId, companyName, onClose }: Props) {
  const token = usePlatformToken();
  const [assignments, setAssignments] = useState<ReviewerAssignment[]>([]);
  const [activeCount, setActiveCount] = useState(0);
  const [allReviewers, setAllReviewers] = useState<ReviewerUser[]>([]);
  const [selectedReviewerId, setSelectedReviewerId] = useState('');
  const [error, setError] = useState('');

  const load = () => {
    if (!token) return;
    Promise.all([
      api.companyReviewerAssignments(token, companyId),
      api.platformReviewers(token),
    ]).then(([a, r]) => {
      setAssignments(a.assignments);
      setActiveCount(a.active_count);
      setAllReviewers(r.reviewers.filter((x) => x.status === 'active'));
    });
  };

  useEffect(() => {
    load();
  }, [token, companyId]);

  const assign = async () => {
    if (!token || !selectedReviewerId) return;
    setError('');
    try {
      await api.assignReviewer(token, companyId, Number(selectedReviewerId));
      setSelectedReviewerId('');
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Assign failed');
    }
  };

  const remove = async (assignmentId: number) => {
    if (!token) return;
    await api.removeReviewerAssignment(token, companyId, assignmentId);
    load();
  };

  const assignedIds = new Set(assignments.filter((a) => a.status === 'active').map((a) => a.reviewer_user.id));

  return (
    <div className="card" style={{ marginTop: '1rem', border: '2px solid #e2e8f0' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <h3 style={{ margin: 0 }}>Reviewers — {companyName}</h3>
        <button type="button" className="btn btn-ghost" onClick={onClose}>
          Close
        </button>
      </div>
      {error && <div className="error">{error}</div>}
      <p style={{ color: '#64748b' }}>
        Active assignments: {activeCount} / 2 (hidden from company admins)
      </p>
      <ul>
        {assignments.map((a) => (
          <li key={a.id} style={{ marginBottom: '0.5rem' }}>
            {a.reviewer_user.name} ({a.reviewer_user.email}) — {a.status}
            {a.status === 'active' && (
              <button type="button" className="btn btn-ghost btn-sm" style={{ marginLeft: '0.5rem' }} onClick={() => remove(a.id)}>
                Remove
              </button>
            )}
          </li>
        ))}
      </ul>
      {activeCount < 2 && (
        <div style={{ display: 'flex', gap: '0.5rem', alignItems: 'center', marginTop: '0.5rem' }}>
          <select value={selectedReviewerId} onChange={(e) => setSelectedReviewerId(e.target.value)}>
            <option value="">Select reviewer…</option>
            {allReviewers
              .filter((r) => !assignedIds.has(r.id))
              .map((r) => (
                <option key={r.id} value={r.id}>
                  {r.name} ({r.email})
                </option>
              ))}
          </select>
          <button type="button" className="btn btn-primary" disabled={!selectedReviewerId} onClick={assign}>
            Assign
          </button>
        </div>
      )}
    </div>
  );
}
