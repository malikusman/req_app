import { useState } from 'react';
import { MessageCirclePlus } from 'lucide-react';
import type { ReviewDiscussion } from '../../../lib/api';
import { Button, Textarea } from '../../../components/ui';
import { cn } from '../../../lib/cn';

type CoConsultantOption = {
  consultant_user_id: number;
  consultant_name: string;
};

export function EvidenceAskBubble({
  anchorType,
  anchorId,
  coConsultants,
  employeeId,
  conversationId,
  discussions,
  onAskConsultant,
  onAskEmployee,
  disabled,
}: {
  anchorType: 'message' | 'finding' | 'section';
  anchorId: string;
  coConsultants: CoConsultantOption[];
  employeeId?: number;
  conversationId?: number;
  discussions: ReviewDiscussion[];
  onAskConsultant: (targetConsultantUserId: number, body: string) => Promise<void>;
  onAskEmployee?: (body: string) => Promise<void>;
  disabled?: boolean;
}) {
  const [open, setOpen] = useState(false);
  const [body, setBody] = useState('');
  const [sending, setSending] = useState(false);
  const [targetConsultantId, setTargetConsultantId] = useState<number | null>(coConsultants[0]?.consultant_user_id ?? null);

  const anchorThreads = discussions.filter(
    (d) => d.anchor_type === anchorType && d.anchor_id === anchorId
  );

  const submitConsultant = async () => {
    if (!targetConsultantId || !body.trim()) return;
    setSending(true);
    try {
      await onAskConsultant(targetConsultantId, body.trim());
      setBody('');
      setOpen(false);
    } finally {
      setSending(false);
    }
  };

  const submitEmployee = async () => {
    if (!onAskEmployee || !body.trim()) return;
    setSending(true);
    try {
      await onAskEmployee(body.trim());
      setBody('');
      setOpen(false);
    } finally {
      setSending(false);
    }
  };

  return (
    <div className="relative">
      <button
        type="button"
        disabled={disabled}
        onClick={() => setOpen((v) => !v)}
        aria-label={open ? 'Close ask panel' : 'Ask a question about this item'}
        aria-expanded={open}
        className={cn(
          'inline-flex h-7 w-7 items-center justify-center rounded-full border border-border bg-background text-muted-foreground shadow-sm hover:bg-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2',
          anchorThreads.length > 0 && 'border-accent text-accent'
        )}
      >
        <MessageCirclePlus className="h-3.5 w-3.5" aria-hidden />
        {anchorThreads.length > 0 && (
          <span className="absolute -right-1 -top-1 flex h-4 min-w-4 items-center justify-center rounded-full bg-accent px-1 text-[10px] text-accent-foreground">
            {anchorThreads.length}
          </span>
        )}
      </button>

      {open && (
        <div className="absolute right-0 z-20 mt-2 w-[min(18rem,calc(100vw-2rem))] rounded-lg border border-border bg-card p-3 shadow-lg">
          <p className="m-0 mb-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">Ask on this</p>
          <Textarea rows={3} value={body} onChange={(e) => setBody(e.target.value)} placeholder="Your question…" />
          {coConsultants.length > 0 && (
            <div className="mt-2 space-y-1">
              <label className="text-xs text-muted-foreground">Co-consultant</label>
              <select
                className="w-full rounded-md border border-border bg-background px-2 py-1.5 text-sm"
                value={targetConsultantId ?? ''}
                onChange={(e) => setTargetConsultantId(Number(e.target.value))}
              >
                {coConsultants.map((cr) => (
                  <option key={cr.consultant_user_id} value={cr.consultant_user_id}>
                    {cr.consultant_name}
                  </option>
                ))}
              </select>
            </div>
          )}
          <div className="mt-3 flex flex-wrap gap-2">
            {coConsultants.length > 0 && (
              <Button size="sm" disabled={!body.trim() || sending} loading={sending} onClick={submitConsultant}>
                Ask co-consultant
              </Button>
            )}
            {employeeId && conversationId && onAskEmployee && (
              <Button size="sm" variant="secondary" disabled={!body.trim() || sending} loading={sending} onClick={submitEmployee}>
                Ask employee
              </Button>
            )}
          </div>
          {anchorThreads.length > 0 && (
            <ul className="mt-3 max-h-32 space-y-2 overflow-y-auto border-t border-border pt-3 text-xs">
              {anchorThreads.map((thread) => (
                <li key={thread.id} className="rounded-md bg-muted/50 p-2">
                  <p className="m-0 font-medium text-foreground">{thread.author_name}</p>
                  <p className="m-0 mt-1 text-muted-foreground">{thread.body}</p>
                </li>
              ))}
            </ul>
          )}
        </div>
      )}
    </div>
  );
}
