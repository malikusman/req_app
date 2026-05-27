import { useEffect, useState } from 'react';
import { api, type ReviewerAssignment, type ReviewerUser } from '../../lib/api';
import { usePlatformToken } from '../../lib/auth';
import { Card, Button, Badge, Select } from '../../components/ui';
import { ExpertReviewerCard } from '../../components/ExpertReviewerCard';

type Props = {
  companyId: number;
  companyName: string;
  onClose?: () => void;
  embedded?: boolean;
};

export function PlatformCompanyReviewers({ companyId, companyName, onClose, embedded }: Props) {
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
  const available = allReviewers.filter((r) => !assignedIds.has(r.id));
  const selectedReviewer = available.find((r) => String(r.id) === selectedReviewerId);

  const content = (
    <>
      {!embedded && (
        <div className="mb-4 flex items-center justify-between">
          <h3 className="m-0 font-medium text-text-primary">Reviewers — {companyName}</h3>
          {onClose && (
            <Button variant="ghost" size="sm" onClick={onClose}>
              Close
            </Button>
          )}
        </div>
      )}
      {error && <p className="text-sm text-status-error">{error}</p>}
      <p className="text-sm text-text-secondary">
        Active assignments: {activeCount} / 2. Published profiles appear to company admins on ready reports.
      </p>
      <ul className="mt-4 space-y-3">
        {assignments.map((a) => (
          <li key={a.id} className="rounded-button border border-border px-3 py-3">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <span className="text-sm font-medium text-text-primary">{a.reviewer_user.name}</span>
              <div className="flex items-center gap-2">
                <Badge variant={a.status === 'active' ? 'success' : 'neutral'}>{a.status}</Badge>
                {a.status === 'active' && (
                  <Button variant="ghost" size="sm" onClick={() => remove(a.id)}>
                    Remove
                  </Button>
                )}
              </div>
            </div>
            {a.reviewer_user.public_card && a.status === 'active' && (
              <div className="mt-3">
                <ExpertReviewerCard reviewer={a.reviewer_user.public_card} compact />
              </div>
            )}
            {a.reviewer_user.profile_status !== 'published' && a.status === 'active' && (
              <p className="mt-2 text-xs text-status-warning">
                Profile {a.reviewer_user.profile_completeness_percent ?? 0}% — not published yet
              </p>
            )}
          </li>
        ))}
      </ul>
      {activeCount < 2 && (
        <div className="mt-4 space-y-4">
          <div className="flex flex-wrap items-end gap-3">
            <Select
              label="Add reviewer"
              value={selectedReviewerId}
              onChange={(e) => setSelectedReviewerId(e.target.value)}
              options={[
                { value: '', label: 'Select reviewer…' },
                ...available.map((r) => ({
                  value: String(r.id),
                  label: `${r.name} (${r.profile_completeness_percent ?? 0}% · ${r.profile_status || 'draft'})`,
                })),
              ]}
              className="min-w-[280px]"
            />
            <Button disabled={!selectedReviewerId} onClick={assign}>
              Assign
            </Button>
          </div>
          {selectedReviewer && (
            <ExpertReviewerCard
              reviewer={
                selectedReviewer.public_card || {
                  id: selectedReviewer.id,
                  name: selectedReviewer.name,
                  headline: selectedReviewer.headline ?? null,
                  avatar_url: selectedReviewer.avatar_url ?? null,
                  expertise_tags: selectedReviewer.expertise_tags ?? [],
                  industries: [],
                  years_experience: null,
                  languages: [],
                  location: null,
                  linkedin_url: null,
                  profile_status: selectedReviewer.profile_status || 'draft',
                  platform_verified: false,
                }
              }
              compact
            />
          )}
        </div>
      )}
    </>
  );

  if (embedded) return <div>{content}</div>;
  return <Card>{content}</Card>;
}
