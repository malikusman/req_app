import { useCallback, useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api, type Report, type ReportArtifact, type ReportVariant } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { BadgeCheck, BookOpen, Copy, Download, FileText, Link2, Ban } from 'lucide-react';
import { PageHeader, Button, Badge, EmptyState, Select, Card, Skeleton } from '../../components/ui';
import { label } from '../../lib/labels';
import { useToast } from '../../components/ui/ToastProvider';

// The report IS the product. It used to be rendered as row one of a DataTable
// with Version / Status / Generated / What changed, read in a 75vh modal iframe
// -- a landscape A4 page scaled into a short box, close to unreadable, with
// nothing on the page saying what the report actually FOUND before you opened it.
//
// So: the latest report becomes the page. The governing thought and the
// expert-validated opportunity render as real selectable text, and the two
// downloads are labelled with honest page counts -- "which one do I want" should
// never require opening both.

function formatAmount(amount: number, unit: string): string {
  const number = amount.toLocaleString('en-US');
  const [currency, period] = unit.split('/').map((part) => part.trim());
  const lead = /^[A-Z]{2,4}$/.test(currency) ? `${currency} ${number}` : `${number} ${currency}`.trim();
  return period ? `${lead} / ${period}` : lead;
}

function pageLabel(artifact: ReportArtifact): string {
  return artifact.page_count ? `${artifact.page_count} pp` : artifact.orientation;
}

export function CompanyReports() {
  const token = useCompanyToken();
  const navigate = useNavigate();
  const { toast } = useToast();
  const [reports, setReports] = useState<Report[]>([]);
  const [detail, setDetail] = useState<Report | null>(null);
  const [stale, setStale] = useState(false);
  const [intelUpdatedAt, setIntelUpdatedAt] = useState<string | null>(null);
  const [error, setError] = useState('');
  const [loadError, setLoadError] = useState('');
  const [loading, setLoading] = useState(true);

  // Chosen expiry for new share links (backend defaults to 30 if unset).
  const [shareDays, setShareDays] = useState('30');

  const load = useCallback(() => {
    if (!token) return;
    api
      .companyReports(token)
      .then((d) => {
        setReports(d.reports);
        setStale(d.report_stale === true);
        setIntelUpdatedAt(d.intelligence_updated_at ?? null);
        setLoadError('');
      })
      .catch(() => setLoadError('Could not load reports.'))
      .finally(() => setLoading(false));
  }, [token]);

  useEffect(() => {
    load();
    const interval = setInterval(load, 5000);
    return () => clearInterval(interval);
  }, [load]);

  const latestReady = useMemo(
    () =>
      reports
        .filter((r) => r.status === 'ready')
        .reduce<Report | null>((latest, r) => (!latest || r.version > latest.version ? r : latest), null),
    [reports]
  );

  // The list endpoint omits report_snapshot (it is large); the hero needs it to
  // render the finding as text, so the latest report is fetched in detail.
  useEffect(() => {
    if (!token || !latestReady) return;
    if (detail?.id === latestReady.id) return;
    let cancelled = false;
    api
      .companyReport(token, latestReady.id)
      .then((d) => {
        if (!cancelled) setDetail(d.report);
      })
      .catch(() => {
        /* the hero degrades to metadata only */
      });
    return () => {
      cancelled = true;
    };
  }, [token, latestReady, detail?.id]);

  // A real reader route, not a modal iframe. A landscape A4 page scaled into a
  // 75vh box was close to unreadable, and a modal can carry neither page
  // navigation nor section jump links.
  const openReader = (report: Report, variant: ReportVariant) =>
    navigate(`/company/reports/${report.id}/read?variant=${variant}`);

  const share = async (id: number, variant: ReportVariant) => {
    if (!token) return;
    try {
      const res = await api.shareReport(token, id, Number(shareDays), variant);
      try {
        await navigator.clipboard.writeText(res.share_url);
        toast({
          variant: 'success',
          title: `${res.variant_label} link copied`,
          description: `Anyone with this link opens the ${res.variant_label.toLowerCase()} — expires in ${shareDays} days.`,
        });
      } catch {
        toast({ variant: 'success', title: `${res.variant_label} link ready`, description: res.share_url });
      }
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Share failed');
    }
  };

  const copyExisting = async (url: string, variantLabel: string) => {
    try {
      await navigator.clipboard.writeText(url);
      toast({ variant: 'success', title: `${variantLabel} link copied` });
    } catch {
      toast({ variant: 'success', title: `${variantLabel} link`, description: url });
    }
  };

  const revokeShare = async (id: number, variant?: ReportVariant) => {
    if (!token) return;
    try {
      await api.revokeReportShare(token, id, variant);
      toast({ variant: 'success', title: 'Link revoked', description: 'That link no longer works.' });
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not revoke the link');
    }
  };

  const generate = async () => {
    if (!token) return;
    try {
      await api.generateReport(token);
      toast({
        variant: 'success',
        title: 'Generating a refreshed report',
        description: "It goes through expert review before it's shared with you.",
      });
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not start generation');
    }
  };

  const download = async (id: number, variant: ReportVariant) => {
    if (!token) return;
    await api.downloadReport(token, id, variant);
  };

  const generating = reports.some((r) => r.status === 'queued' || r.status === 'generating');
  const hero = detail?.id === latestReady?.id ? detail : latestReady;
  const snapshot = hero?.report_snapshot;
  const finding =
    snapshot?.narrative?.governing_thought?.trim() ||
    snapshot?.situation?.headline?.trim() ||
    snapshot?.executive_summary?.split(/(?<=\.)\s+/)[0]?.trim() ||
    null;
  const opportunity = snapshot?.expert?.opportunity ?? null;
  const validators = snapshot?.expert?.validators ?? [];
  const artifacts = hero?.artifacts ?? [];
  const olderReports = reports.filter((r) => r.id !== hero?.id);

  return (
    <div className="space-y-8">
      <PageHeader
        title="Reports"
        description="Your discovery reports — read, download, or share."
        actions={
          <div className="flex flex-wrap items-center gap-2">
            <span className="hidden text-xs text-muted-foreground sm:inline">New links expire in</span>
            <Select
              aria-label="Share link expiry"
              value={shareDays}
              onChange={(e) => setShareDays(e.target.value)}
              options={[
                { value: '7', label: '7 days' },
                { value: '30', label: '30 days' },
                { value: '90', label: '90 days' },
              ]}
            />
          </div>
        }
      />

      {error && <p className="text-sm text-status-error">{error}</p>}
      {loadError && (
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-button border border-status-error/30 bg-status-errorBg px-4 py-3 text-sm text-status-error">
          <span>{loadError}</span>
          <Button size="sm" variant="secondary" onClick={load}>
            Retry
          </Button>
        </div>
      )}

      {generating && (
        <div className="rounded-button border border-info/30 bg-info/10 px-4 py-3 text-sm text-info">
          A report is being generated — this page will update automatically when it's ready.
        </div>
      )}

      {stale && !generating && (
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-button border border-warning/30 bg-warning/10 px-4 py-3 text-sm text-warning">
          <span>
            Your intelligence has changed
            {intelUpdatedAt && ` (updated ${new Date(intelUpdatedAt).toLocaleString()})`} since your latest report.
          </span>
          <Button size="sm" variant="secondary" onClick={generate}>
            Generate refreshed report
          </Button>
        </div>
      )}

      {loading && !hero && (
        <Card className="space-y-4 p-6">
          <Skeleton className="h-4 w-32" />
          <Skeleton className="h-20 w-full" />
          <Skeleton className="h-10 w-64" />
        </Card>
      )}

      {!loading && !hero && (
        <EmptyState
          icon={FileText}
          title="No reports yet"
          description="Your first report appears here once discovery has enough evidence."
          action={{ label: 'Back to dashboard', onClick: () => navigate('/company/dashboard') }}
        />
      )}

      {/* ---- The hero: what the report found, before anything is downloaded ---- */}
      {hero && (
        <Card className="overflow-hidden p-0">
          <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border px-6 py-4">
            <div className="flex flex-wrap items-center gap-2">
              {validators.length > 0 && (
                <Badge variant="success">
                  <BadgeCheck className="mr-1 inline h-3 w-3" />
                  Expert validated
                </Badge>
              )}
              <Badge variant="info">{label('reportStatus', hero.status)}</Badge>
            </div>
            <div className="text-xs text-text-secondary">
              v{hero.version}
              {hero.generated_at && ` · ${new Date(hero.generated_at).toLocaleDateString()}`}
            </div>
          </div>

          <div className="grid gap-8 px-6 py-6 lg:grid-cols-[1.5fr_1fr]">
            <div className="space-y-5">
              {finding ? (
                <p className="text-xl font-semibold leading-snug text-text-primary">{finding}</p>
              ) : (
                <p className="text-sm text-text-secondary">
                  Open the report to read the findings — the summary text isn't available for this version.
                </p>
              )}

              {snapshot?.narrative?.stakes && (
                <p className="text-sm leading-relaxed text-text-secondary">
                  <span className="font-medium text-text-primary">What's at stake: </span>
                  {snapshot.narrative.stakes}
                </p>
              )}

              {validators.length > 0 && (
                <div className="space-y-1 border-l-2 border-accent pl-3">
                  {validators.map((v) => (
                    <div key={v.name} className="text-xs text-text-secondary">
                      Validated by <span className="font-medium text-text-primary">{v.name}</span>
                      {v.credential && ` · ${v.credential}`}
                    </div>
                  ))}
                </div>
              )}

              {(snapshot?.key_metrics?.length ?? 0) > 0 && (
                <div className="grid gap-4 sm:grid-cols-3">
                  {snapshot!.key_metrics!.slice(0, 3).map((m) => (
                    <div key={`${m.headline}-${m.label}`} className="border-t-2 border-border pt-2">
                      <div className="text-lg font-semibold text-text-primary">{m.headline}</div>
                      {m.comparison && <div className="text-xs font-medium text-status-error">{m.comparison}</div>}
                      <div className="mt-0.5 text-xs leading-snug text-text-secondary">{m.label}</div>
                    </div>
                  ))}
                </div>
              )}
            </div>

            {/* The opportunity figure. It was collected in the review workspace
                and reached no PDF and no page at all until now. */}
            <div className="space-y-5 lg:border-l lg:border-border lg:pl-8">
              {opportunity ? (
                <div>
                  <div className="text-xs font-semibold uppercase tracking-wider text-text-secondary">
                    Identified opportunity
                  </div>
                  <div className="mt-2 text-3xl font-bold leading-none text-accent">
                    {formatAmount(opportunity.amount, opportunity.unit)}
                  </div>
                  {opportunity.basis && (
                    <p className="mt-3 text-sm leading-relaxed text-text-secondary">{opportunity.basis}</p>
                  )}
                  <div className="mt-2 text-xs text-muted-foreground">
                    Sized by {opportunity.consultant}
                    {opportunity.consultant_credential && ` · ${opportunity.consultant_credential}`}
                  </div>
                </div>
              ) : (
                <div className="text-xs text-muted-foreground">
                  An opportunity figure appears here once an expert has sized one.
                </div>
              )}

              {/* Two labelled downloads with honest page counts -- "which one do
                  I want" should never require opening both. */}
              <div className="space-y-3 border-t border-border pt-5">
                {artifacts.length === 0 && (
                  <Button variant="secondary" size="sm" onClick={() => download(hero.id, 'full')}>
                    <Download className="mr-1.5 h-3.5 w-3.5" />
                    Download report
                  </Button>
                )}
                {artifacts.map((artifact) => (
                  <div key={artifact.variant} className="space-y-1.5">
                    <div className="flex flex-wrap items-center gap-2">
                      <Button size="sm" onClick={() => openReader(hero, artifact.variant)}>
                        <BookOpen className="mr-1.5 h-3.5 w-3.5" />
                        Read {artifact.label.toLowerCase()} · {pageLabel(artifact)}
                      </Button>
                      <Button
                        variant="secondary"
                        size="sm"
                        aria-label={`Download ${artifact.label}`}
                        onClick={() => download(hero.id, artifact.variant)}
                      >
                        <Download className="h-3.5 w-3.5" />
                      </Button>
                      <Button
                        variant="secondary"
                        size="sm"
                        aria-label={`Share ${artifact.label}`}
                        onClick={() => share(hero.id, artifact.variant)}
                      >
                        <Link2 className="h-3.5 w-3.5" />
                      </Button>
                    </div>
                    <p className="text-xs leading-snug text-muted-foreground">{artifact.description}</p>
                  </div>
                ))}
              </div>

              {/* Per-variant links, each labelled with what it opens. */}
              {(hero.shares?.length ?? 0) > 0 && (
                <div className="space-y-2 border-t border-border pt-5">
                  <div className="text-xs font-semibold uppercase tracking-wider text-text-secondary">
                    Active links
                  </div>
                  {hero.shares!.map((s) => (
                    <div key={s.id} className="flex flex-wrap items-center gap-2 text-xs text-text-secondary">
                      <Badge variant="success">{s.variant_label}</Badge>
                      <span>expires {new Date(s.expires_at).toLocaleDateString()}</span>
                      {s.access_count > 0 && (
                        <span>
                          · {s.access_count} view{s.access_count === 1 ? '' : 's'}
                        </span>
                      )}
                      <button
                        type="button"
                        className="inline-flex items-center gap-1 text-accent hover:underline"
                        onClick={() => copyExisting(s.share_url, s.variant_label)}
                      >
                        <Copy className="h-3 w-3" /> Copy
                      </button>
                      <button
                        type="button"
                        className="inline-flex items-center gap-1 text-status-error hover:underline"
                        onClick={() => revokeShare(hero.id, s.variant)}
                      >
                        <Ban className="h-3 w-3" /> Revoke
                      </button>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>

          {hero.delta_summary && (
            <div className="border-t border-border bg-surface-subtle px-6 py-3 text-xs text-text-secondary">
              <span className="font-medium text-text-primary">What changed: </span>
              {hero.delta_summary}
            </div>
          )}
        </Card>
      )}

      {/* ---- Earlier versions, deliberately quiet ---- */}
      {olderReports.length > 0 && (
        <div className="space-y-2">
          <h2 className="text-sm font-semibold text-text-primary">Earlier versions</h2>
          <div className="divide-y divide-border rounded-card border border-border">
            {olderReports.map((r) => (
              <div key={r.id} className="flex flex-wrap items-center justify-between gap-3 px-4 py-3">
                <div className="min-w-0">
                  <div className="flex items-center gap-2 text-sm text-text-primary">
                    v{r.version}
                    {r.status !== 'ready' && (
                      <Badge variant={r.status === 'failed' ? 'error' : 'info'}>
                        {label('reportStatus', r.status)}
                      </Badge>
                    )}
                    <span className="text-xs text-muted-foreground">
                      {r.generated_at ? new Date(r.generated_at).toLocaleDateString() : '—'}
                    </span>
                  </div>
                  {r.delta_summary && (
                    <div className="truncate text-xs text-text-secondary">{r.delta_summary}</div>
                  )}
                </div>
                {r.status === 'ready' && (
                  <div className="flex flex-wrap gap-2">
                    {(r.artifacts ?? [{ variant: 'full', label: 'Report' } as ReportArtifact]).map((a) => (
                      <Button
                        key={a.variant}
                        variant="secondary"
                        size="sm"
                        onClick={() => openReader(r, a.variant)}
                      >
                        {a.label}
                      </Button>
                    ))}
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>
      )}

    </div>
  );
}
