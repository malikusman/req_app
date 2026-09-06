import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from '@/components/shadcn/sheet';
import { ConsultantCoConsultantChatPanel } from '../ConsultantCoConsultantChatPanel';

export function ConsultantChatDrawer({
  companyId,
  open,
  onOpenChange,
  coConsultantNames,
  onMessagesLoaded,
}: {
  companyId: number;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  coConsultantNames?: string[];
  onMessagesLoaded?: (latestId: number | null) => void;
}) {
  const subtitle =
    coConsultantNames && coConsultantNames.length > 0
      ? `With ${coConsultantNames.join(' and ')}`
      : 'Private channel with co-consultants on this assignment.';

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="right" className="flex w-full flex-col p-0 sm:max-w-[380px]">
        <SheetHeader className="border-b border-border px-6 py-4 text-left">
          <SheetTitle>Co-consultant chat</SheetTitle>
          <SheetDescription>{subtitle}</SheetDescription>
        </SheetHeader>
        <div className="flex min-h-0 flex-1 flex-col px-4 py-4">
          <ConsultantCoConsultantChatPanel
            companyId={companyId}
            active={open}
            onMessagesLoaded={onMessagesLoaded}
          />
        </div>
      </SheetContent>
    </Sheet>
  );
}
