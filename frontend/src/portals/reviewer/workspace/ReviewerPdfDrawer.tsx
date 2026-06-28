import { Download } from 'lucide-react';
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from '@/components/shadcn/sheet';
import { Button } from '../../../components/ui';

export function ReviewerPdfDrawer({
  open,
  onOpenChange,
  previewUrl,
  downloadUrl,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  previewUrl: string | null;
  downloadUrl: string | null;
}) {
  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="right" className="flex w-full flex-col p-0 sm:max-w-[60vw]">
        <SheetHeader className="border-b border-border px-6 py-4 text-left">
          <SheetTitle>Client PDF</SheetTitle>
          <SheetDescription>Deliverable report artifact — reference while reviewing evidence.</SheetDescription>
          {downloadUrl && (
            <a href={downloadUrl} target="_blank" rel="noreferrer" className="inline-flex pt-2">
              <Button variant="secondary" size="sm" icon={<Download className="h-4 w-4" />}>
                Download PDF
              </Button>
            </a>
          )}
        </SheetHeader>
        <div className="min-h-0 flex-1 bg-muted/30 p-4">
          {previewUrl ? (
            <iframe
              src={previewUrl}
              title="Report PDF preview"
              className="h-full min-h-[70vh] w-full rounded-lg border border-border bg-background"
            />
          ) : (
            <p className="text-sm text-muted-foreground">PDF preview unavailable.</p>
          )}
        </div>
      </SheetContent>
    </Sheet>
  );
}
