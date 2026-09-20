import { Download } from 'lucide-react';
import type { ReportVariant } from '@/lib/api';
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from '@/components/shadcn/sheet';
import { Button } from '../../../components/ui';

// The reviewer has to be able to SEE the executive brief before submitting.
// Four pages is where a weak governing thought does maximum damage — there is no
// surrounding detail to soften it — and the brief is the artifact a client
// actually forwards.
export function ConsultantPdfDrawer({
  open,
  onOpenChange,
  previewUrl,
  draftUrl,
  downloadUrl,
  mode,
  onModeChange,
  variant,
  onVariantChange,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  previewUrl: string | null;
  draftUrl: string | null;
  downloadUrl: string | null;
  mode: 'stored' | 'draft';
  onModeChange: (mode: 'stored' | 'draft') => void;
  variant: ReportVariant;
  onVariantChange: (variant: ReportVariant) => void;
}) {
  const url = mode === 'draft' ? draftUrl : previewUrl;

  const pill = (active: boolean) =>
    `rounded-full px-3 py-1 text-xs font-medium transition ${
      active ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground hover:text-foreground'
    }`;

  const tab = (value: 'stored' | 'draft', label: string) => (
    <button type="button" onClick={() => onModeChange(value)} className={pill(mode === value)}>
      {label}
    </button>
  );

  const variantTab = (value: ReportVariant, label: string) => (
    <button
      type="button"
      onClick={() => onVariantChange(value)}
      // The stored artifact is only fetched for the full report; the brief is
      // reviewable in the live "with your edits" render.
      disabled={mode === 'stored' && value !== 'full'}
      className={`${pill(variant === value)} disabled:cursor-not-allowed disabled:opacity-40`}
    >
      {label}
    </button>
  );

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="right" className="flex w-full flex-col p-0 sm:max-w-[60vw]">
        <SheetHeader className="border-b border-border px-6 py-4 text-left">
          <SheetTitle>Report preview</SheetTitle>
          <SheetDescription>
            {mode === 'draft'
              ? 'Live render with your pending section edits applied — what the client gets on approval.'
              : 'The last generated deliverable artifact.'}
          </SheetDescription>
          <div className="flex flex-wrap items-center gap-2 pt-2">
            {tab('draft', 'With your edits')}
            {tab('stored', 'Stored PDF')}
            <span className="mx-1 h-4 w-px bg-border" aria-hidden />
            {variantTab('full', 'Full report')}
            {variantTab('exec_brief', 'Executive brief · 4pp')}
            {downloadUrl && (
              <a href={downloadUrl} target="_blank" rel="noreferrer" className="ml-auto inline-flex">
                <Button variant="secondary" size="sm" icon={<Download className="h-4 w-4" />}>
                  Download PDF
                </Button>
              </a>
            )}
          </div>
        </SheetHeader>
        <div className="min-h-0 flex-1 bg-muted/30 p-4">
          {url ? (
            <iframe
              src={url}
              title="Report preview"
              className="h-full min-h-[70vh] w-full rounded-lg border border-border bg-background"
            />
          ) : (
            <p className="text-sm text-muted-foreground">
              {mode === 'draft' ? 'Building preview…' : 'PDF preview unavailable.'}
            </p>
          )}
        </div>
      </SheetContent>
    </Sheet>
  );
}
