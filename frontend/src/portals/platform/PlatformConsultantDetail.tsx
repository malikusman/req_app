import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { FileText } from 'lucide-react';
import { api, type ConsultantUser, type ConsultantPublicCard } from '../../lib/api';
import { usePlatformToken } from '../../lib/auth';
import { PageHeader, Card, Button, Badge, Skeleton } from '../../components/ui';
import { ExpertConsultantCard } from '../../components/ExpertConsultantCard';

function toPublicCard(consultant: ConsultantUser): ConsultantPublicCard {
  if (consultant.public_card) return consultant.public_card;
  const p = consultant.profile;
  return {
    id: consultant.id,
    name: consultant.name,
    headline: p?.headline ?? consultant.headline ?? null,
    bio: p?.bio ?? null,
    avatar_url: p?.avatar_url ?? consultant.avatar_url ?? null,
    expertise_tags: p?.expertise_tags ?? consultant.expertise_tags ?? [],
    industries: p?.industries ?? [],
    years_experience: p?.years_experience ?? null,
    languages: p?.languages ?? [],
    location: p?.location ?? null,
    linkedin_url: p?.linkedin_url ?? null,
    profile_status: p?.profile_status ?? consultant.profile_status ?? 'draft',
    platform_verified: Boolean(p?.platform_verified_at),
    experiences: p?.experiences ?? [],
  };
}

export function PlatformConsultantDetail() {
  const { id } = useParams();
  const consultantId = Number(id);
  const token = usePlatformToken();
  const [consultant, setConsultant] = useState<ConsultantUser | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [cvLoading, setCvLoading] = useState(false);

  useEffect(() => {
    if (!token || !consultantId) return;
    setLoading(true);
    api
      .platformConsultant(token, consultantId)
      .then((d) => setConsultant(d.consultant))
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load consultant'))
      .finally(() => setLoading(false));
  }, [token, consultantId]);

  const openCv = async () => {
    if (!token || !consultantId) return;
    setCvLoading(true);
    setError('');
    try {
      const url = await api.platformConsultantCvUrl(token, consultantId);
      window.open(url, '_blank', 'noopener,noreferrer');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not open CV');
    } finally {
      setCvLoading(false);
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

  if (!consultant) {
    return (
      <div className="space-y-4">
        <PageHeader title="Consultant" description={error || 'Not found'} />
        <Link to="/platform/consultants">
          <Button variant="secondary">Back to consultants</Button>
        </Link>
      </div>
    );
  }

  const hasCv = Boolean(consultant.has_cv || consultant.profile?.has_cv);

  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <PageHeader
        title={consultant.name}
        description={consultant.email}
        breadcrumbs={[
          { label: 'Consultants', href: '/platform/consultants' },
          { label: consultant.name },
        ]}
        actions={
          <div className="flex flex-wrap gap-2">
            {hasCv ? (
              <Button variant="secondary" loading={cvLoading} onClick={openCv}>
                <FileText className="mr-1.5 h-4 w-4" />
                View CV
              </Button>
            ) : null}
            <Link to="/platform/consultants">
              <Button variant="secondary">Back</Button>
            </Link>
          </div>
        }
      />

      {error ? <p className="text-sm text-status-error">{error}</p> : null}

      <div className="flex flex-wrap gap-2">
        <Badge variant={consultant.status === 'active' ? 'success' : 'neutral'}>{consultant.status}</Badge>
        {consultant.profile_status === 'published' ? (
          <Badge variant="success">Published</Badge>
        ) : (
          <Badge variant="warning">Draft · {consultant.profile_completeness_percent ?? 0}%</Badge>
        )}
        {hasCv ? <Badge variant="info">CV on file</Badge> : null}
      </div>

      <ExpertConsultantCard consultant={toPublicCard(consultant)} token={token} />

      {consultant.assignments && consultant.assignments.length > 0 ? (
        <Card title="Active company assignments">
          <ul className="m-0 space-y-2 p-0">
            {consultant.assignments.map((a) => (
              <li key={a.company_id} className="list-none">
                <Link
                  to={`/platform/companies/${a.company_id}`}
                  className="text-sm font-medium text-primary hover:underline"
                >
                  {a.company_name}
                </Link>
              </li>
            ))}
          </ul>
        </Card>
      ) : (
        <Card title="Active company assignments">
          <p className="m-0 text-sm text-muted-foreground">Not assigned to any company.</p>
        </Card>
      )}
    </div>
  );
}
