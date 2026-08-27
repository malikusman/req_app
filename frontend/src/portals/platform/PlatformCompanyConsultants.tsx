import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { api, type ConsultantAssignment, type ConsultantUser, type ConsultantPublicCard } from '../../lib/api';
import { usePlatformToken } from '../../lib/auth';
import { Card, Button, Badge } from '../../components/ui';
import { ExpertConsultantCard } from '../../components/ExpertConsultantCard';

type Props = {
  companyId: number;
  companyName: string;
  onClose?: () => void;
  embedded?: boolean;
};

function toPublicCard(r: ConsultantUser): ConsultantPublicCard {
  return (
    r.public_card || {
      id: r.id,
      name: r.name,
      headline: r.headline ?? null,
      bio: null,
      avatar_url: r.avatar_url ?? null,
      expertise_tags: r.expertise_tags ?? [],
      industries: [],
      years_experience: null,
      languages: [],
      location: null,
      linkedin_url: null,
      profile_status: r.profile_status || 'draft',
      platform_verified: false,
      experiences: [],
    }
  );
}

export function PlatformCompanyConsultants({ companyId, companyName, onClose, embedded }: Props) {
  const token = usePlatformToken();
  const [assignments, setAssignments] = useState<ConsultantAssignment[]>([]);
  const [activeCount, setActiveCount] = useState(0);
  const [allConsultants, setAllConsultants] = useState<ConsultantUser[]>([]);
  const [error, setError] = useState('');
  const [assigningId, setAssigningId] = useState<number | null>(null);

  const load = () => {
    if (!token) return;
    Promise.all([api.companyConsultantAssignments(token, companyId), api.platformConsultants(token)]).then(([a, r]) => {
      setAssignments(a.assignments);
      setActiveCount(a.active_count);
      setAllConsultants(r.consultants.filter((x) => x.status === 'active'));
    });
  };

  useEffect(() => {
    load();
  }, [token, companyId]);

  const assign = async (consultantUserId: number) => {
    if (!token) return;
    setError('');
    setAssigningId(consultantUserId);
    try {
      await api.assignConsultant(token, companyId, consultantUserId);
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Assign failed');
    } finally {
      setAssigningId(null);
    }
  };

  const remove = async (assignmentId: number) => {
    if (!token) return;
    await api.removeConsultantAssignment(token, companyId, assignmentId);
    load();
  };

  const assignedIds = new Set(assignments.filter((a) => a.status === 'active').map((a) => a.consultant_user.id));
  const available = allConsultants.filter((r) => !assignedIds.has(r.id));
  const activeAssignments = assignments.filter((a) => a.status === 'active');
  const pastAssignments = assignments.filter((a) => a.status !== 'active');

  const content = (
    <div className="space-y-6">
      {!embedded && (
        <div className="flex items-center justify-between">
          <h3 className="m-0 font-medium text-text-primary">Consultants — {companyName}</h3>
          {onClose && (
            <Button variant="ghost" size="sm" onClick={onClose}>
              Close
            </Button>
          )}
        </div>
      )}
      {error ? <p className="text-sm text-status-error">{error}</p> : null}
      <p className="m-0 text-sm text-text-secondary">
        Active assignments: {activeCount} / 2. Published profiles appear to company admins.
      </p>

      <section className="space-y-3">
        <h4 className="m-0 text-sm font-medium text-foreground">Assigned</h4>
        {activeAssignments.length === 0 ? (
          <p className="m-0 text-sm text-muted-foreground">No consultants assigned yet. Pick from the cards below.</p>
        ) : (
          <div className="grid gap-4 md:grid-cols-2">
            {activeAssignments.map((a) => (
              <ExpertConsultantCard
                key={a.id}
                consultant={toPublicCard(a.consultant_user)}
                token={token}
                footer={
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <div className="flex flex-wrap items-center gap-2">
                      <Badge variant="success">Assigned</Badge>
                      {a.consultant_user.profile_status === 'published' ? (
                        <Badge variant="success">Published</Badge>
                      ) : (
                        <Badge variant="warning">
                          Draft · {a.consultant_user.profile_completeness_percent ?? 0}%
                        </Badge>
                      )}
                    </div>
                    <div className="flex gap-2">
                      <Link to={`/platform/consultants/${a.consultant_user.id}`}>
                        <Button variant="secondary" size="sm">
                          View
                        </Button>
                      </Link>
                      <Button variant="ghost" size="sm" onClick={() => remove(a.id)}>
                        Remove
                      </Button>
                    </div>
                  </div>
                }
              />
            ))}
          </div>
        )}
      </section>

      {activeCount < 2 ? (
        <section className="space-y-3">
          <h4 className="m-0 text-sm font-medium text-foreground">Available to assign</h4>
          {available.length === 0 ? (
            <p className="m-0 text-sm text-muted-foreground">No other active consultants available.</p>
          ) : (
            <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
              {available.map((r) => (
                <ExpertConsultantCard
                  key={r.id}
                  consultant={toPublicCard(r)}
                  compact
                  token={token}
                  footer={
                    <div className="flex flex-wrap items-center justify-between gap-2">
                      <div className="flex flex-wrap gap-1">
                        {r.profile_status === 'published' ? (
                          <Badge variant="success">Published</Badge>
                        ) : (
                          <Badge variant="neutral">Draft · {r.profile_completeness_percent ?? 0}%</Badge>
                        )}
                      </div>
                      <div className="flex gap-2">
                        <Link to={`/platform/consultants/${r.id}`}>
                          <Button variant="ghost" size="sm">
                            View
                          </Button>
                        </Link>
                        <Button
                          size="sm"
                          loading={assigningId === r.id}
                          disabled={activeCount >= 2}
                          onClick={() => assign(r.id)}
                        >
                          Assign
                        </Button>
                      </div>
                    </div>
                  }
                />
              ))}
            </div>
          )}
        </section>
      ) : (
        <p className="m-0 text-sm text-muted-foreground">Assignment limit reached (2). Remove one to assign another.</p>
      )}

      {pastAssignments.length > 0 ? (
        <section className="space-y-2">
          <h4 className="m-0 text-sm font-medium text-muted-foreground">Previously assigned</h4>
          <ul className="m-0 space-y-1 p-0">
            {pastAssignments.map((a) => (
              <li key={a.id} className="flex list-none items-center justify-between text-sm text-muted-foreground">
                <span>{a.consultant_user.name}</span>
                <Badge variant="neutral">{a.status}</Badge>
              </li>
            ))}
          </ul>
        </section>
      ) : null}
    </div>
  );

  if (embedded) return <div>{content}</div>;
  return <Card>{content}</Card>;
}
