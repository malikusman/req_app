import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { api, type Report, type ReportArtifact, type ReportVariant } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { ArrowLeft, ChevronLeft, ChevronRight, Download, Maximize2, MoveHorizontal } from 'lucide-react';
import { Button, Skeleton } from '../../components/ui';

// A real document reader, replacing the modal iframe.
//
// The report was previously read as a landscape A4 page scaled into a 75vh
// modal box, which was close to unreadable, had no page navigation, and no way
// to jump to a section. We already render the report as HTML, so this is a
// viewer, not a converter: the reader loads the stored HTML behind the approved
// PDF and drives it, which is what makes real section jump links possible.

// The report's own page geometry, in CSS pixels at 96dpi. These mirror the
// --pw/--ph custom properties in the report stylesheets (297x210mm landscape,
// 210x297mm portrait); the reader scales to fit rather than guessing.
const PAGE_PX: Record<ReportVariant, { w: number; h: number }> = {
  full: { w: 1123, h: 794 },
  exec_brief: { w: 794, h: 1123 },
};

type Section = { title: string; pageIndex: number };
type FitMode = 'width' | 'page';

// Injected into the reader iframe. Strips the inter-page gap that the report
// stylesheet uses for screen preview so one page fills the frame exactly, and
// suppresses the page's own scrollbar (the reader owns navigation).
const READER_CSS = `
  html, body { margin: 0 !important; padding: 0 !important; background: transparent !important; }
  body { overflow: hidden !important; }
  .page { margin: 0 auto !important; box-shadow: none !important; }
  .refbar { display: none !important; }
`;

export function CompanyReportReader() {
  const { id } = useParams();
  const reportId = Number(id);
  const token = useCompanyToken();
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();

  const variantParam = searchParams.get('variant');
  const variant: ReportVariant = variantParam === 'exec_brief' ? 'exec_brief' : 'full';

  const [report, setReport] = useState<Report | null>(null);
  const [html, setHtml] = useState<string | null>(null);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);

  const [sections, setSections] = useState<Section[]>([]);
  const [pageCount, setPageCount] = useState(0);
  const [current, setCurrent] = useState(0);
  const [fit, setFit] = useState<FitMode>('page');
  const [scale, setScale] = useState(1);

  const iframeRef = useRef<HTMLIFrameElement>(null);
  const stageRef = useRef<HTMLDivElement>(null);
  // Scrolling the frame ourselves fires the observer; without this the
  // indicator fights the click that caused the jump.
  const programmaticScroll = useRef(false);

  const geometry = PAGE_PX[variant];

  useEffect(() => {
    if (!token || !reportId) return;
    setLoading(true);
    setError('');
    Promise.all([api.companyReport(token, reportId), api.readCompanyReport(token, reportId, variant)])
      .then(([detail, markup]) => {
        setReport(detail.report);
        setHtml(markup);
      })
      .catch((e) =>
        setError(
          e instanceof Error && e.message
            ? e.message
            : 'This report has no readable version. Download the PDF instead.'
        )
      )
      .finally(() => setLoading(false));
  }, [token, reportId, variant]);

  // Scale to fit. Recomputed on resize and whenever the fit mode or the paper
  // orientation changes, so a landscape page is actually legible.
  const recomputeScale = useCallback(() => {
    const stage = stageRef.current;
    if (!stage) return;
    const padding = 32;
    const availableWidth = stage.clientWidth - padding;
    const availableHeight = stage.clientHeight - padding;
    const byWidth = availableWidth / geometry.w;
    const next = fit === 'width' ? byWidth : Math.min(byWidth, availableHeight / geometry.h);
    setScale(Math.max(0.2, Math.min(next, 2)));
  }, [fit, geometry.h, geometry.w]);

  useEffect(() => {
    recomputeScale();
    window.addEventListener('resize', recomputeScale);
    return () => window.removeEventListener('resize', recomputeScale);
  }, [recomputeScale]);

  // Read the page structure out of the loaded document. srcdoc is same-origin,
  // so the section titles come from the report's own markup rather than from a
  // duplicate table of contents maintained on this side.
  const onFrameLoad = useCallback(() => {
    const doc = iframeRef.current?.contentDocument;
    if (!doc) return;

    const style = doc.createElement('style');
    style.textContent = READER_CSS;
    doc.head.appendChild(style);

    const pages = Array.from(doc.querySelectorAll<HTMLElement>('section.page'));
    setPageCount(pages.length);

    // What labels a jump target is not obvious, and getting it wrong makes the
    // rail useless either way:
    //
    //   * <h1> is an action title -- a McKinsey-style assertion like "Core
    //     system dependency is the deepest recurring friction, cited across 9
    //     pieces of evidence". Right for the page, unreadable in a nav rail.
    //   * .eyebrow IS the section name ("Signals", "Recommendations"), so it is
    //     the label -- except on consultant-authored pages, where every eyebrow
    //     reads "Expert consultant" and four distinct sections would collapse
    //     into one target. There the <h1> is the real section name.
    const found: Section[] = [];
    pages.forEach((page, index) => {
      const clean = (value: string | null | undefined) =>
        (value ?? '').replace(/\s+/g, ' ').replace(/\s*·\s*continued$/i, '').trim();
      const heading = clean(page.querySelector('h1')?.textContent);
      const eyebrow = clean(page.querySelector('.eyebrow, .cat')?.textContent);
      const authored = page.classList.contains('expert-page');
      const title = (authored ? heading || eyebrow : eyebrow || heading) || `Page ${index + 1}`;

      // Consecutive pages of one section (Signals, Signals · continued) collapse
      // to a single jump target rather than repeating in the rail.
      const previous = found[found.length - 1];
      if (previous && previous.title === title) return;
      found.push({ title, pageIndex: index });
    });
    setSections(found);

    // Keep the indicator honest when the reader is scrolled by hand.
    const observer = new IntersectionObserver(
      (entries) => {
        if (programmaticScroll.current) return;
        const visible = entries
          .filter((e) => e.isIntersecting)
          .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];
        if (!visible) return;
        const index = pages.indexOf(visible.target as HTMLElement);
        if (index >= 0) setCurrent(index);
      },
      { root: doc.documentElement, threshold: [0.25, 0.5, 0.75] }
    );
    pages.forEach((page) => observer.observe(page));
  }, []);

  const goTo = useCallback(
    (index: number) => {
      const doc = iframeRef.current?.contentDocument;
      if (!doc) return;
      const pages = doc.querySelectorAll<HTMLElement>('section.page');
      const clamped = Math.max(0, Math.min(index, pages.length - 1));
      programmaticScroll.current = true;
      pages[clamped]?.scrollIntoView({ block: 'start' });
      setCurrent(clamped);
      window.setTimeout(() => {
        programmaticScroll.current = false;
      }, 250);
    },
    []
  );

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'ArrowRight' || e.key === 'PageDown') {
        e.preventDefault();
        goTo(current + 1);
      } else if (e.key === 'ArrowLeft' || e.key === 'PageUp') {
        e.preventDefault();
        goTo(current - 1);
      } else if (e.key === 'Escape') {
        navigate('/company/reports');
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [current, goTo, navigate]);

  const artifacts: ReportArtifact[] = report?.artifacts ?? [];
  const activeArtifact = artifacts.find((a) => a.variant === variant);

  const switchVariant = (next: ReportVariant) => {
    setSearchParams({ variant: next }, { replace: true });
    setCurrent(0);
    setSections([]);
    setPageCount(0);
  };

  const download = () => {
    if (token) api.downloadReport(token, reportId, variant);
  };

  const stageStyle = useMemo(
    () => ({ width: geometry.w * scale, height: geometry.h * scale }),
    [geometry.h, geometry.w, scale]
  );

  return (
    <div className="flex h-[calc(100vh-2rem)] flex-col gap-3">
      {/* ---- Reader chrome ---- */}
      <div className="flex flex-wrap items-center gap-2 border-b border-border pb-3">
        <Button variant="secondary" size="sm" onClick={() => navigate('/company/reports')}>
          <ArrowLeft className="mr-1.5 h-3.5 w-3.5" />
          Reports
        </Button>

        <div className="min-w-0 text-sm font-medium text-text-primary">
          {activeArtifact?.label ?? 'Report'}
          {report && <span className="text-text-secondary"> · v{report.version}</span>}
        </div>

        {artifacts.length > 1 && (
          <div className="ml-2 flex items-center gap-1 rounded-full bg-surface-muted p-0.5">
            {artifacts.map((a) => (
              <button
                key={a.variant}
                type="button"
                onClick={() => switchVariant(a.variant)}
                className={`rounded-full px-3 py-1 text-xs font-medium transition ${
                  a.variant === variant
                    ? 'bg-primary text-primary-foreground'
                    : 'text-text-secondary hover:text-text-primary'
                }`}
              >
                {a.label}
                {a.page_count ? ` · ${a.page_count}pp` : ''}
              </button>
            ))}
          </div>
        )}

        <div className="ml-auto flex items-center gap-2">
          <div className="flex items-center gap-1 rounded-full bg-surface-muted p-0.5">
            <button
              type="button"
              aria-label="Fit whole page"
              onClick={() => setFit('page')}
              className={`rounded-full p-1.5 transition ${
                fit === 'page' ? 'bg-primary text-primary-foreground' : 'text-text-secondary'
              }`}
            >
              <Maximize2 className="h-3.5 w-3.5" />
            </button>
            <button
              type="button"
              aria-label="Fit width"
              onClick={() => setFit('width')}
              className={`rounded-full p-1.5 transition ${
                fit === 'width' ? 'bg-primary text-primary-foreground' : 'text-text-secondary'
              }`}
            >
              <MoveHorizontal className="h-3.5 w-3.5" />
            </button>
          </div>

          <div className="flex items-center gap-1">
            <Button
              variant="secondary"
              size="sm"
              aria-label="Previous page"
              disabled={current === 0}
              onClick={() => goTo(current - 1)}
            >
              <ChevronLeft className="h-3.5 w-3.5" />
            </Button>
            <span className="min-w-[4.5rem] text-center text-xs tabular-nums text-text-secondary">
              {pageCount ? `${current + 1} of ${pageCount}` : '—'}
            </span>
            <Button
              variant="secondary"
              size="sm"
              aria-label="Next page"
              disabled={pageCount === 0 || current >= pageCount - 1}
              onClick={() => goTo(current + 1)}
            >
              <ChevronRight className="h-3.5 w-3.5" />
            </Button>
          </div>

          <Button variant="secondary" size="sm" onClick={download}>
            <Download className="mr-1.5 h-3.5 w-3.5" />
            PDF
          </Button>
        </div>
      </div>

      {error && (
        <div className="rounded-button border border-status-error/30 bg-status-errorBg px-4 py-3 text-sm text-status-error">
          {error}{' '}
          <button type="button" className="underline" onClick={download}>
            Download the PDF
          </button>
        </div>
      )}

      <div className="flex min-h-0 flex-1 gap-4">
        {/* ---- Section jump list. The whole reason for rendering HTML rather
                than showing a page image. ---- */}
        <nav className="hidden w-56 shrink-0 overflow-y-auto lg:block" aria-label="Report sections">
          {sections.length === 0 && loading && (
            <div className="space-y-2">
              {[0, 1, 2, 3, 4].map((i) => (
                <Skeleton key={i} className="h-6 w-full" />
              ))}
            </div>
          )}
          <ol className="space-y-0.5">
            {sections.map((section, i) => {
              const next = sections[i + 1]?.pageIndex ?? pageCount;
              const active = current >= section.pageIndex && current < next;
              return (
                <li key={`${section.title}-${section.pageIndex}`}>
                  <button
                    type="button"
                    onClick={() => goTo(section.pageIndex)}
                    className={`w-full border-l-2 px-3 py-1.5 text-left text-xs leading-snug transition ${
                      active
                        ? 'border-accent bg-accent/5 font-medium text-text-primary'
                        : 'border-transparent text-text-secondary hover:border-border hover:text-text-primary'
                    }`}
                  >
                    {section.title}
                  </button>
                </li>
              );
            })}
          </ol>
        </nav>

        {/* ---- The page itself ---- */}
        <div
          ref={stageRef}
          className="flex min-h-0 flex-1 items-start justify-center overflow-auto rounded-card bg-surface-muted p-4"
        >
          {loading && !html ? (
            <Skeleton className="h-full w-full" />
          ) : html ? (
            <div style={stageStyle} className="shrink-0 shadow-lg">
              <iframe
                ref={iframeRef}
                srcDoc={html}
                onLoad={onFrameLoad}
                title="Report"
                // Sandboxed: the report is our own markup, but it is generated
                // content carrying consultant-authored text, so it gets no
                // script execution and no access to the parent origin.
                sandbox="allow-same-origin"
                style={{
                  width: geometry.w,
                  height: geometry.h,
                  transform: `scale(${scale})`,
                  transformOrigin: 'top left',
                  border: 0,
                  background: '#fff',
                }}
              />
            </div>
          ) : null}
        </div>
      </div>
    </div>
  );
}
