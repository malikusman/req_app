import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { CheckCircle2, FileUp, Mic, Pause, Send } from 'lucide-react';
import { ChatMessageList, type ChatMessageItem } from '../../../components/motion';
import { Badge, Button, Card, Textarea } from '../../../components/ui';
import {
  api,
  type LeadershipConversation,
  type LeadershipDoor,
  type LeadershipPersonInput,
} from '../../../lib/api';
import { ScopeCard } from './ScopeCard';
import { useVoiceRecorder, voiceRecordingSupported } from './useVoiceNote';

const PROGRESS_LABELS: Record<string, string> = {
  early: 'Just started',
  middle: 'Under way',
  near_end: 'Nearly done',
  done: 'Finished',
};

const DOCUMENT_TYPES =
  'application/pdf,image/jpeg,image/png,image/webp,text/csv,text/plain,' +
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document,' +
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,' +
  'application/vnd.openxmlformats-officedocument.presentationml.presentation';

function formatSeconds(total: number) {
  return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, '0')}`;
}

/**
 * The conversation with leadership (Doc 08), for the key user in the portal and
 * for a manager by their link. One question at a time; type or send a voice
 * note; pause any time. The key user also gets the scope card near the end.
 * A participant sees their own conversation only — never what was captured.
 */
export function LeadershipChat({ door, keyUserToken }: { door: LeadershipDoor; keyUserToken?: string | null }) {
  const [data, setData] = useState<LeadershipConversation | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [draft, setDraft] = useState('');
  const [sending, setSending] = useState(false);
  const [pending, setPending] = useState<string | null>(null);
  const [warnings, setWarnings] = useState<string[]>([]);
  const recorder = useVoiceRecorder();
  const fileRef = useRef<HTMLInputElement>(null);
  const uploadFor = useRef<number | undefined>(undefined);

  const run = useCallback(async (step: () => Promise<LeadershipConversation>) => {
    setError('');
    try {
      const next = await step();
      setData(next);
      if (next.warnings) setWarnings(next.warnings);
      return next;
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Something went wrong. Please try again.');
      return null;
    }
  }, []);

  useEffect(() => {
    let active = true;
    void (async () => {
      const first = await run(() => api.leadershipShow(door));
      // Back after a break: a brief welcome, then the same thread.
      if (active && first?.session?.needs_resume && first.available) await run(() => api.leadershipResume(door));
      if (active) setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [door, run]);

  const session = data?.session ?? null;
  const finished = Boolean(session?.finished);
  const paused = session?.state === 'PAUSED';

  const messages: ChatMessageItem[] = useMemo(() => {
    const turns: ChatMessageItem[] = (session?.turns ?? []).map((t) => ({
      id: t.index,
      // The participant's words on the right, as in any messaging app.
      direction: t.from === 'participant' ? 'outbound' : 'inbound',
      body: t.text,
      timestamp: t.at,
      meta:
        t.input_mode === 'VOICE_NOTE' ? (
          <span className="inline-flex items-center gap-1 text-xs font-medium text-muted-foreground">
            <Mic className="h-3 w-3" /> Voice note
          </span>
        ) : undefined,
    }));
    if (pending) turns.push({ id: 'pending', direction: 'outbound', body: pending, timestamp: new Date() });
    return turns;
  }, [session, pending]);

  const send = async (text: string) => {
    if (!text.trim() || sending) return;
    setSending(true);
    setPending(text.trim());
    setDraft('');
    const id = typeof crypto !== 'undefined' && 'randomUUID' in crypto ? crypto.randomUUID() : String(Date.now());
    const next = await run(() => api.leadershipMessage(door, text.trim(), id));
    if (!next) setDraft(text);
    setPending(null);
    setSending(false);
  };

  const sendVoiceNote = async () => {
    const file = await recorder.stop();
    if (!file) return;
    setSending(true);
    setPending('Listening to your voice note…');
    await run(() => api.leadershipVoiceNote(door, file));
    setPending(null);
    setSending(false);
  };

  const pickFile = (requestId?: number) => {
    uploadFor.current = requestId;
    fileRef.current?.click();
  };

  if (loading) {
    return <p className="p-6 text-sm text-muted-foreground">Loading your conversation…</p>;
  }

  if (!data) {
    return <p className="p-6 text-sm text-destructive">{error || 'This conversation could not be opened.'}</p>;
  }

  if (!session && !data.available) {
    return (
      <Card title="Your conversation with Mjadi">
        <p className="m-0 text-sm text-muted-foreground">
          The Mjadi team will be in touch to arrange your conversation.
        </p>
      </Card>
    );
  }

  if (!session || !data.participant.consented) {
    return (
      <Card title="Before we start">
        <div className="space-y-4">
          <p className="m-0 text-sm text-foreground">
            A short conversation, about fifteen to twenty minutes, to understand where you're taking the business and
            what gets in the way. You can type or send voice notes.
          </p>
          <ul className="m-0 space-y-2 pl-5 text-sm text-muted-foreground" dir="auto">
            {data.consent.points.map((point) => (
              <li key={point}>{point}</li>
            ))}
          </ul>
          {error && <p className="m-0 text-sm text-destructive">{error}</p>}
          <Button onClick={() => void run(() => api.leadershipConsent(door))}>I understand — let's start</Button>
        </div>
      </Card>
    );
  }

  const showScope =
    data.scope && (session.state === 'SCOPE_AND_PARTICIPANTS' || (finished && !data.scope.counts_known));
  const openRequests = session.document_requests;

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-4">
      <div className="flex items-center justify-between gap-3">
        <div className="flex items-center gap-2">
          <Badge variant={finished ? 'success' : 'info'}>{PROGRESS_LABELS[session.progress] ?? 'Under way'}</Badge>
          {paused && <span className="text-xs text-muted-foreground">Paused — carry on whenever you like</span>}
        </div>
        {!finished && !paused && (
          <Button
            variant="ghost"
            size="sm"
            icon={<Pause className="h-4 w-4" />}
            disabled={sending}
            onClick={() => void run(() => api.leadershipPause(door))}
          >
            Pause
          </Button>
        )}
      </div>

      {(error || recorder.error) && (
        <p className="m-0 rounded-md bg-destructive/10 px-3 py-2 text-sm text-destructive">{error || recorder.error}</p>
      )}

      <div className="flex min-h-[420px] flex-1 flex-col overflow-hidden rounded-xl border border-border bg-card shadow-sm">
        <ChatMessageList messages={messages} className="min-h-0 flex-1 px-3 py-4 sm:px-4" showTyping={sending} />

        {session.themes.length > 0 && !finished && (
          <div className="border-t border-border bg-muted/40 px-4 py-3" dir="auto">
            <p className="m-0 mb-1 text-xs font-semibold uppercase tracking-wide text-muted-foreground">
              What we've heard
            </p>
            <ul className="m-0 space-y-1 pl-5 text-sm text-foreground">
              {session.themes.map((theme) => (
                <li key={theme}>{theme}</li>
              ))}
            </ul>
          </div>
        )}

        {finished ? (
          <div className="flex items-center gap-2 border-t border-border px-4 py-4 text-sm text-foreground">
            <CheckCircle2 className="h-4 w-4 text-status-success" />
            Thank you — that's everything we need. The team will be in touch about the next step.
          </div>
        ) : recorder.recording ? (
          <div className="flex items-center gap-3 border-t border-border px-4 py-3">
            <span className="h-3 w-3 shrink-0 animate-pulse rounded-full bg-destructive" aria-hidden />
            <span className="text-sm font-medium">Recording {formatSeconds(recorder.seconds)}</span>
            <div className="ml-auto flex gap-2">
              <Button variant="ghost" onClick={recorder.cancel}>Cancel</Button>
              <Button onClick={() => void sendVoiceNote()} icon={<Send className="h-4 w-4" />}>Send</Button>
            </div>
          </div>
        ) : (
          <form
            className="flex items-end gap-2 border-t border-border px-3 py-3 sm:px-4"
            onSubmit={(e) => {
              e.preventDefault();
              void send(draft);
            }}
          >
            <div className="min-w-0 flex-1">
              <Textarea
                aria-label="Your answer"
                dir="auto"
                value={draft}
                disabled={sending}
                placeholder="Type your answer…"
                className="min-h-[72px] max-h-40 w-full resize-none text-base"
                onChange={(e) => setDraft(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter' && !e.shiftKey) {
                    e.preventDefault();
                    void send(draft);
                  }
                }}
              />
            </div>
            {voiceRecordingSupported() && (
              <Button
                type="button"
                variant="secondary"
                aria-label="Send a voice note"
                className="h-11 w-11 shrink-0 p-0"
                disabled={sending}
                icon={<Mic className="h-5 w-5" />}
                onClick={() => void recorder.start()}
              />
            )}
            <Button type="submit" className="h-11 shrink-0 px-4" disabled={sending || !draft.trim()} icon={<Send className="h-4 w-4" />}>
              Send
            </Button>
          </form>
        )}
      </div>

      <input
        ref={fileRef}
        type="file"
        accept={DOCUMENT_TYPES}
        className="sr-only"
        onChange={(e) => {
          const file = e.target.files?.[0];
          e.target.value = '';
          if (file) void run(() => api.leadershipDocument(door, file, uploadFor.current));
        }}
      />

      {openRequests.length > 0 && (
        <Card title="Documents you mentioned">
          <div className="space-y-2">
            <p className="m-0 text-sm text-muted-foreground">Optional — share them now or later.</p>
            {openRequests.map((r) => (
              <div key={r.id} className="flex items-center justify-between gap-3 rounded-md bg-muted/50 px-3 py-2">
                <span className="min-w-0 text-sm text-foreground" dir="auto">{r.requested_item}</span>
                {r.status === 'RECEIVED' ? (
                  <Badge variant="success">Thanks — got it</Badge>
                ) : r.status === 'REQUESTED' ? (
                  <Button size="sm" variant="secondary" icon={<FileUp className="h-3.5 w-3.5" />} onClick={() => pickFile(r.id)}>
                    Upload
                  </Button>
                ) : (
                  <Badge variant="neutral">Not needed</Badge>
                )}
              </div>
            ))}
            <Button size="sm" variant="ghost" icon={<FileUp className="h-3.5 w-3.5" />} onClick={() => pickFile()}>
              Share something else
            </Button>
          </div>
        </Card>
      )}

      {showScope && data.scope && keyUserToken && (
        <ScopeCard
          scope={data.scope}
          warnings={warnings}
          onSave={async (rows) => {
            await run(() => api.leadershipScope(keyUserToken, rows));
          }}
          onConfirmPerson={async (index: number, person: LeadershipPersonInput) => {
            await run(() => api.leadershipConfirmPerson(keyUserToken, index, person));
          }}
          onDismissPerson={async (index: number) => {
            await run(() => api.leadershipDismissPerson(keyUserToken, index));
          }}
        />
      )}
    </div>
  );
}
