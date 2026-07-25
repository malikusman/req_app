import { useEffect, useState, type ReactNode } from 'react';
import { ExternalLink, MapPin } from 'lucide-react';
import { api, type ReviewerPublicCard } from '../lib/api';
import { Badge, Card } from './ui';
import { cn } from '../lib/cn';

type Props = {
  reviewer: ReviewerPublicCard;
  compact?: boolean;
  /** Required for authenticated avatar fetch (platform / company / reviewer token). */
  token?: string | null;
  footer?: ReactNode;
  className?: string;
};

function formatYears(start?: number | null, end?: number | null) {
  if (!start) return null;
  return end ? `${start}–${end}` : `${start}–present`;
}

export function ExpertReviewerCard({ reviewer, compact, token, footer, className }: Props) {
  const [avatarPreview, setAvatarPreview] = useState<string | null>(null);
  const tags = reviewer.expertise_tags || [];
  const industries = reviewer.industries || [];
  const languages = reviewer.languages || [];
  const experiences = reviewer.experiences || [];
  const visibleTags = tags.slice(0, compact ? 3 : 8);
  const visibleIndustries = industries.slice(0, compact ? 2 : 6);

  useEffect(() => {
    if (!token || !reviewer.avatar_url) {
      setAvatarPreview(null);
      return;
    }
    let cancelled = false;
    let objectUrl: string | null = null;
    api
      .fetchReviewerAvatarPreview(token, reviewer.avatar_url)
      .then((url) => {
        if (cancelled) {
          URL.revokeObjectURL(url);
          return;
        }
        objectUrl = url;
        setAvatarPreview(url);
      })
      .catch(() => {
        /* keep initials fallback */
      });
    return () => {
      cancelled = true;
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [token, reviewer.avatar_url]);

  const photo = avatarPreview ? (
    <img
      src={avatarPreview}
      alt=""
      className={cn('shrink-0 rounded-full object-cover', compact ? 'h-12 w-12' : 'h-20 w-20')}
    />
  ) : (
    <div
      className={cn(
        'flex shrink-0 items-center justify-center rounded-full bg-muted font-semibold text-muted-foreground',
        compact ? 'h-12 w-12 text-base' : 'h-20 w-20 text-2xl'
      )}
    >
      {reviewer.name.charAt(0)}
    </div>
  );

  if (compact) {
    return (
      <Card className={cn('p-4', className)}>
        <div className="flex gap-3">
          {photo}
          <div className="min-w-0 flex-1">
            <div className="flex flex-wrap items-center gap-2">
              <h4 className="m-0 truncate text-sm font-medium text-foreground">{reviewer.name}</h4>
              {reviewer.platform_verified ? <Badge variant="success">Verified</Badge> : null}
            </div>
            {reviewer.headline ? (
              <p className="mt-0.5 line-clamp-2 text-xs text-muted-foreground">{reviewer.headline}</p>
            ) : null}
            {visibleTags.length > 0 ? (
              <div className="mt-2 flex flex-wrap gap-1">
                {visibleTags.map((tag) => (
                  <Badge key={tag} variant="neutral">
                    {tag}
                  </Badge>
                ))}
              </div>
            ) : null}
          </div>
        </div>
        {footer ? <div className="mt-3 border-t border-border pt-3">{footer}</div> : null}
      </Card>
    );
  }

  return (
    <Card className={cn('overflow-hidden p-0', className)}>
      <div className="bg-gradient-to-br from-primary/10 via-background to-muted/40 px-5 pb-4 pt-5">
        <div className="flex gap-4">
          {photo}
          <div className="min-w-0 flex-1">
            <div className="flex flex-wrap items-center gap-2">
              <h3 className="m-0 text-lg font-medium text-foreground">{reviewer.name}</h3>
              {reviewer.platform_verified ? <Badge variant="success">Worktruth verified</Badge> : null}
            </div>
            {reviewer.headline ? <p className="mt-1 text-sm text-muted-foreground">{reviewer.headline}</p> : null}
            <div className="mt-2 flex flex-wrap gap-x-3 gap-y-1 text-xs text-muted-foreground">
              {reviewer.location ? (
                <span className="inline-flex items-center gap-1">
                  <MapPin className="h-3 w-3" />
                  {reviewer.location}
                </span>
              ) : null}
              {reviewer.years_experience != null ? <span>{reviewer.years_experience}+ years experience</span> : null}
              {languages.length > 0 ? <span>{languages.join(', ')}</span> : null}
            </div>
          </div>
        </div>
      </div>

      <div className="space-y-4 px-5 py-4">
        {reviewer.bio ? (
          <p className="m-0 whitespace-pre-wrap text-sm leading-relaxed text-foreground/90">{reviewer.bio}</p>
        ) : null}

        {visibleTags.length > 0 ? (
          <div>
            <p className="mb-1.5 text-xs font-medium uppercase tracking-wide text-muted-foreground">Strengths</p>
            <div className="flex flex-wrap gap-1.5">
              {visibleTags.map((tag) => (
                <Badge key={tag} variant="neutral">
                  {tag}
                </Badge>
              ))}
            </div>
          </div>
        ) : null}

        {visibleIndustries.length > 0 ? (
          <div>
            <p className="mb-1.5 text-xs font-medium uppercase tracking-wide text-muted-foreground">Industries</p>
            <div className="flex flex-wrap gap-1.5">
              {visibleIndustries.map((ind) => (
                <Badge key={ind} variant="info">
                  {ind}
                </Badge>
              ))}
            </div>
          </div>
        ) : null}

        {experiences.length > 0 ? (
          <div>
            <p className="mb-1.5 text-xs font-medium uppercase tracking-wide text-muted-foreground">Experience</p>
            <ul className="m-0 space-y-2 p-0">
              {experiences.slice(0, 4).map((exp, idx) => (
                <li key={exp.id ?? `${exp.organization}-${idx}`} className="list-none text-sm">
                  <p className="m-0 font-medium text-foreground">
                    {exp.title}
                    {exp.organization ? <span className="font-normal text-muted-foreground"> · {exp.organization}</span> : null}
                  </p>
                  {formatYears(exp.start_year, exp.end_year) ? (
                    <p className="m-0 text-xs text-muted-foreground">{formatYears(exp.start_year, exp.end_year)}</p>
                  ) : null}
                </li>
              ))}
            </ul>
          </div>
        ) : null}

        {reviewer.linkedin_url ? (
          <a
            href={reviewer.linkedin_url}
            target="_blank"
            rel="noreferrer"
            className="inline-flex items-center gap-1.5 text-sm font-medium text-primary hover:underline"
          >
            LinkedIn profile
            <ExternalLink className="h-3.5 w-3.5" />
          </a>
        ) : null}

        {footer ? <div className="border-t border-border pt-3">{footer}</div> : null}
      </div>
    </Card>
  );
}
