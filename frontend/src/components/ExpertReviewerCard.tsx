import { Badge, Card } from './ui';
import type { ReviewerPublicCard } from '../lib/api';

type Props = {
  reviewer: ReviewerPublicCard;
  compact?: boolean;
};

export function ExpertReviewerCard({ reviewer, compact }: Props) {
  return (
    <Card className={compact ? 'p-4' : undefined}>
      <div className="flex gap-4">
        {reviewer.avatar_url ? (
          <img
            src={reviewer.avatar_url}
            alt=""
            className="h-14 w-14 shrink-0 rounded-full object-cover"
          />
        ) : (
          <div className="flex h-14 w-14 shrink-0 items-center justify-center rounded-full bg-surface-muted text-lg font-semibold text-text-secondary">
            {reviewer.name.charAt(0)}
          </div>
        )}
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <h4 className="m-0 text-base font-medium text-text-primary">{reviewer.name}</h4>
            {reviewer.platform_verified && (
              <Badge variant="success">Req verified</Badge>
            )}
          </div>
          {reviewer.headline && (
            <p className="mt-1 text-sm text-text-secondary">{reviewer.headline}</p>
          )}
          {reviewer.years_experience != null && (
            <p className="mt-1 text-xs text-text-secondary">{reviewer.years_experience}+ years experience</p>
          )}
          {reviewer.expertise_tags.length > 0 && (
            <div className="mt-2 flex flex-wrap gap-1">
              {reviewer.expertise_tags.slice(0, compact ? 3 : 6).map((tag) => (
                <Badge key={tag} variant="neutral">
                  {tag}
                </Badge>
              ))}
            </div>
          )}
          {reviewer.linkedin_url && !compact && (
            <a
              href={reviewer.linkedin_url}
              target="_blank"
              rel="noreferrer"
              className="mt-2 inline-block text-sm font-medium text-accent hover:underline"
            >
              LinkedIn profile
            </a>
          )}
        </div>
      </div>
    </Card>
  );
}
