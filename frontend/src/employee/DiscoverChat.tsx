import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { Paperclip, X } from 'lucide-react';
import { ChatMessageList, type ChatMessageItem } from '../components/motion';
import { Button, Textarea } from '../components/ui';
import {
  clearDiscoverToken,
  discoverApi,
  getStoredDiscoverToken,
  type DiscoverState,
} from './discoverApi';

const ACCEPTED_TYPES = 'image/jpeg,image/png,image/webp,application/pdf';

function mapMessages(messages: { id: number; direction: 'inbound' | 'outbound'; body: string; created_at: string }[]): ChatMessageItem[] {
  return messages.map((m) => ({
    id: m.id,
    direction: m.direction,
    body: m.body,
    timestamp: m.created_at,
  }));
}

export function DiscoverChat() {
  const { token = '' } = useParams();
  const navigate = useNavigate();
  const jwt = getStoredDiscoverToken();
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [messages, setMessages] = useState<ChatMessageItem[]>([]);
  const [state, setState] = useState<DiscoverState | null>(null);
  const [draft, setDraft] = useState('');
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);
  const [processingMedia, setProcessingMedia] = useState(false);

  const load = useCallback(async () => {
    if (!jwt) return;
    const data = await discoverApi.messages(jwt);
    setMessages(mapMessages(data.messages));
    setState(data.state);
    return data;
  }, [jwt]);

  useEffect(() => {
    if (!jwt) {
      navigate(`/discover/${token}`, { replace: true });
      return;
    }

    load()
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load chat'))
      .finally(() => setLoading(false));
  }, [jwt, load, navigate, token]);

  const pollForFollowUp = useCallback(
    async (baselineCount: number) => {
      if (!jwt) return;
      for (let attempt = 0; attempt < 30; attempt += 1) {
        await new Promise((resolve) => setTimeout(resolve, 2000));
        const data = await discoverApi.messages(jwt);
        setMessages(mapMessages(data.messages));
        setState(data.state);
        if (data.messages.length > baselineCount) {
          setProcessingMedia(false);
          return;
        }
      }
      setProcessingMedia(false);
    },
    [jwt]
  );

  const send = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!jwt || sending) return;

    if (selectedFile) {
      setError('');
      setSending(true);
      const caption = draft.trim();
      const file = selectedFile;
      setDraft('');
      setSelectedFile(null);
      try {
        const data = await discoverApi.sendAttachment(jwt, file, caption || undefined);
        setMessages(mapMessages(data.messages));
        setState(data.state);
        setProcessingMedia(true);
        void pollForFollowUp(data.messages.length);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Failed to upload file');
        setDraft(caption);
        setSelectedFile(file);
      } finally {
        setSending(false);
      }
      return;
    }

    if (!draft.trim()) return;
    setError('');
    setSending(true);
    const text = draft.trim();
    setDraft('');
    try {
      const data = await discoverApi.sendMessage(jwt, text);
      setMessages(mapMessages(data.messages));
      setState(data.state);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to send message');
      setDraft(text);
    } finally {
      setSending(false);
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      void send(e);
    }
  };

  const canAttach =
    state?.conversation_status === 'discovery' || Boolean(state?.completed);
  const canSend = Boolean(selectedFile || draft.trim());

  const statusLabel = useMemo(() => {
    if (!state) return null;
    if (processingMedia) return 'Processing your file…';
    if (state.completed) return 'Interview complete — you can always add more anytime';
    if (state.conversation_status === 'discovery') return 'Discovery in progress';
    if (state.conversation_status === 'profiling') return 'Getting to know your role';
    if (state.onboarding_step === 'awaiting_consent') return 'Please review consent and reply YES to continue';
    return 'Getting started';
  }, [state, processingMedia]);

  if (loading) {
    return (
      <div className="flex h-dvh items-center justify-center bg-background">
        <p className="text-muted-foreground">Loading chat…</p>
      </div>
    );
  }

  return (
    <div className="flex h-dvh flex-col overflow-hidden bg-background">
      <header className="shrink-0 border-b border-border bg-card/80 px-4 py-3 backdrop-blur-sm">
        <div className="mx-auto flex max-w-3xl items-center justify-between gap-3">
          <div className="min-w-0">
            <h1 className="truncate text-lg font-semibold text-foreground">Discovery interview</h1>
            {statusLabel && <p className="truncate text-sm text-muted-foreground">{statusLabel}</p>}
          </div>
          <Button
            variant="ghost"
            size="sm"
            className="shrink-0"
            onClick={() => {
              clearDiscoverToken();
              navigate(`/discover/${token}`, { replace: true });
            }}
          >
            Sign out
          </Button>
        </div>
      </header>

      <div className="mx-auto flex w-full max-w-3xl min-h-0 flex-1 flex-col px-3 py-3 sm:px-4">
        {error && (
          <p className="mb-2 shrink-0 rounded-md bg-destructive/10 px-3 py-2 text-sm text-destructive">
            {error}
          </p>
        )}

        <div className="flex min-h-0 flex-1 flex-col overflow-hidden rounded-xl border border-border bg-card shadow-sm">
          <ChatMessageList
            messages={messages}
            className="min-h-0 flex-1 px-3 py-4 sm:px-4"
            showTyping={sending || processingMedia}
          />

          <form
            onSubmit={send}
            className="shrink-0 border-t border-border bg-background/95 px-3 py-3 backdrop-blur-sm sm:px-4 sm:py-4"
          >
            {state?.completed && (
              <p className="mb-3 text-sm text-muted-foreground">
                Interview complete — but you can always add more anytime.
              </p>
            )}
            {selectedFile && (
              <div className="mb-3 flex items-center gap-2 rounded-lg bg-muted px-3 py-2 text-sm">
                <Paperclip className="h-4 w-4 shrink-0 text-muted-foreground" />
                <span className="min-w-0 flex-1 truncate text-foreground">{selectedFile.name}</span>
                <button
                  type="button"
                  onClick={() => setSelectedFile(null)}
                  className="rounded p-1 text-muted-foreground hover:bg-background hover:text-foreground"
                  aria-label="Remove file"
                >
                  <X className="h-4 w-4" />
                </button>
              </div>
            )}

            <div className="flex items-end gap-2">
              <input
                ref={fileInputRef}
                type="file"
                accept={ACCEPTED_TYPES}
                className="sr-only"
                disabled={!canAttach || sending || processingMedia}
                onChange={(e) => {
                  const file = e.target.files?.[0];
                  if (file) setSelectedFile(file);
                  e.target.value = '';
                }}
              />
              <Button
                type="button"
                variant="secondary"
                disabled={!canAttach || sending || processingMedia}
                onClick={() => fileInputRef.current?.click()}
                aria-label="Attach image or PDF"
                className="h-11 w-11 shrink-0 p-0"
                icon={<Paperclip className="h-5 w-5" />}
              />

              <div className="min-w-0 flex-1">
                <Textarea
                  value={draft}
                  onChange={(e) => setDraft(e.target.value)}
                  onKeyDown={handleKeyDown}
                  placeholder={
                    selectedFile
                      ? 'Add a caption (optional)…'
                      : state?.completed
                        ? 'Share anything else that comes to mind…'
                        : 'Type your reply…'
                  }
                  disabled={sending || processingMedia}
                  className="min-h-[72px] max-h-40 w-full resize-none text-base sm:min-h-[88px]"
                />
              </div>

              <Button
                type="submit"
                disabled={sending || processingMedia || !canSend}
                className="h-11 shrink-0 px-4 sm:px-5"
              >
                Send
              </Button>
            </div>
            <p className="mt-2 hidden text-xs text-muted-foreground sm:block">
              Enter to send · Shift+Enter for a new line
              {canAttach ? ' · Attach images or PDFs during discovery' : ''}
            </p>
          </form>
        </div>
      </div>
    </div>
  );
}
