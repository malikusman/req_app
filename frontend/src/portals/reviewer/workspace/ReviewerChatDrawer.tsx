import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from '@/components/shadcn/sheet';
import { ReviewerCoReviewerChatPanel } from '../ReviewerCoReviewerChatPanel';

export function ReviewerChatDrawer({
  companyId,
  open,
  onOpenChange,
  coReviewerNames,
  onMessagesLoaded,
}: {
  companyId: number;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  coReviewerNames?: string[];
  onMessagesLoaded?: (latestId: number | null) => void;
}) {
  const subtitle =
    coReviewerNames && coReviewerNames.length > 0
      ? `With ${coReviewerNames.join(' and ')}`
      : 'Private channel with co-reviewers on this assignment.';

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="right" className="flex w-full flex-col p-0 sm:max-w-[380px]">
        <SheetHeader className="border-b border-border px-6 py-4 text-left">
          <SheetTitle>Co-reviewer chat</SheetTitle>
          <SheetDescription>{subtitle}</SheetDescription>
        </SheetHeader>
        <div className="flex min-h-0 flex-1 flex-col px-4 py-4">
          <ReviewerCoReviewerChatPanel
            companyId={companyId}
            active={open}
            onMessagesLoaded={onMessagesLoaded}
          />
        </div>
      </SheetContent>
    </Sheet>
  );
}
