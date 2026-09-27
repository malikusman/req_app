import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { Mic, Paperclip, Send, Volume2, VolumeX, X } from 'lucide-react';
import { ChatMessageList, type ChatMessageItem } from '../components/motion';
import { Button, Textarea } from '../components/ui';
import {
  clearDiscoverToken,
  discoverApi,
  getStoredDiscoverToken,
  type DiscoverState,
  type DiscoverMessage,
} from './discoverApi';
import { useVoiceRecorder, voiceRecordingSupported } from './useVoiceRecorder';
import { useReadAloud } from './useReadAloud';

const ACCEPTED_TYPES = 'image/jpeg,image/png,image/webp,application/pdf';

// A question from a named human expert should not read as the assistant's own
// voice, so consultant follow-ups carry a label above the message body.
const CONSULTANT_LABEL = 'Question from the expert reviewing your company';

function formatSeconds(total: number) {
  return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, '0')}`;
}

function mapMessages(
  messages: DiscoverMessage[],
  voice: { onPlay?: (m: DiscoverMessage) => void; speakingId: number | null }
): ChatMessageItem[] {
  return messages.map((m) => {
    const spoken = m.message_type === 'audio' && m.direction === 'inbound';
    const consultant = m.track === 'consultant_followup' && m.direction === 'outbound';
    return {
      id: m.id,
      // Drawn from the employee's side, as in any messaging app: their own words
      // on the right, the interviewer's on the left. The stored direction is the
      // system's (inbound = from the employee), which the operator views keep.
      direction: m.direction === 'inbound' ? 'outbound' : 'inbound',
      // A spoken answer shows its transcript once it has one — what the interview heard.
      body: spoken && !m.body?.trim() ? 'Transcribing your answer…' : m.body,
      timestamp: m.created_at,
      meta: consultant ? (
        <span className="text-xs font-semibold text-primary">{CONSULTANT_LABEL}</span>
      ) : spoken ? (
        <span className="inline-flex items-center gap-1 text-xs font-medium text-muted-foreground">
          <Mic className="h-3 w-3" /> Spoken answer
        </span>
      ) : voice.speakingId === m.id ? (
        <span className="inline-flex items-center gap-1 text-xs font-medium text-primary">
          <Volume2 className="h-3 w-3" /> Reading aloud
        </span>
      ) : undefined,
      actions:
        voice.onPlay && m.direction === 'outbound' && m.body?.trim() ? (
          <button
            type="button"
            onClick={() => voice.onPlay?.(m)}
            className="rounded p-1 text-muted-foreground hover:bg-muted hover:text-foreground"
            aria-label="Read this aloud"
          >
            <Volume2 className="h-4 w-4" />
          </button>
        ) : undefined,
    };
  });
}

export function DiscoverChat() {
  const { token = '' } = useParams();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  // Chosen on the landing page: the waiting question is read out on arrival.
  const startedInVoice = searchParams.get('voice') === '1';
  const jwt = getStoredDiscoverToken(token);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [raw, setRaw] = useState<DiscoverMessage[]>([]);
  const [state, setState] = useState<DiscoverState | null>(null);
  const [draft, setDraft] = useState('');
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);
  const [processingMedia, setProcessingMedia] = useState(false);
  const [voiceUpload, setVoiceUpload] = useState(false);
  const recorder = useVoiceRecorder();
  const readAloud = useReadAloud(jwt, state);
  // The newest interviewer message already heard (or already on screen when the
  // page opened), so each question is read out once, when it arrives.
  const lastSpokenRef = useRef<number | null>(null);

  const messages = useMemo(
    () =>
      mapMessages(raw, {
        onPlay: (m) => void readAloud.speak(m.id, m.body),
        speakingId: readAloud.speakingId,
      }),
    [raw, readAloud]
  );

  useEffect(() => {
    const latest = [...raw].reverse().find((m) => m.direction === 'outbound' && m.body?.trim());
    if (!latest) return;
    if (lastSpokenRef.current === null) {
      lastSpokenRef.current = latest.id;
      if (readAloud.enabled && startedInVoice) void readAloud.speak(latest.id, latest.body);
      return;
    }
    if (latest.id > lastSpokenRef.current) {
      lastSpokenRef.current = latest.id;
      if (readAloud.enabled && !recorder.recording) void readAloud.speak(latest.id, latest.body);
    }
  }, [raw, readAloud, recorder.recording, startedInVoice]);

  const load = useCallback(async () => {
    if (!jwt) return;
    const data = await discoverApi.messages(jwt);
    setRaw(data.messages);
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
        setRaw(data.messages);
        setState(data.state);
        if (data.messages.length > baselineCount) {
          setProcessingMedia(false);
          setVoiceUpload(false);
          return;
        }
      }
      setProcessingMedia(false);
      setVoiceUpload(false);
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
        setRaw(data.messages);
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
    // Shown the moment it is sent; the server's copy replaces it with the reply.
    setRaw((prev) => [
      ...prev,
      {
        id: -Date.now(),
        direction: 'inbound',
        message_type: 'text',
        body: text,
        is_discovery_question: false,
        created_at: new Date().toISOString(),
      },
    ]);
    try {
      const data = await discoverApi.sendMessage(jwt, text);
      setRaw(data.messages);
      setState(data.state);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to send message');
      setRaw((prev) => prev.filter((m) => m.id >= 0));
      setDraft(text);
    } finally {
      setSending(false);
    }
  };

  // Answering out loud: the recording goes up like any attachment, is transcribed,
  // and the transcript is the answer the interview works from.
  const startRecording = async () => {
    readAloud.stop();
    setError('');
    await recorder.start();
  };

  const sendRecording = async () => {
    const file = await recorder.stop();
    if (!file || !jwt) return;
    setError('');
    setSending(true);
    setVoiceUpload(true);
    try {
      const data = await discoverApi.sendAttachment(jwt, file);
      setRaw(data.messages);
      setState(data.state);
      setProcessingMedia(true);
      void pollForFollowUp(data.messages.length);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not send your answer');
      setVoiceUpload(false);
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
  const canRecord = Boolean(state?.voice?.recording) && voiceRecordingSupported();
  const canReadAloud =
    Boolean(state?.voice?.speech) || (typeof window !== 'undefined' && 'speechSynthesis' in window);

  const statusLabel = useMemo(() => {
    if (!state) return null;
    if (processingMedia) return voiceUpload ? 'Listening to your answer…' : 'Processing your file…';
    if (state.completed) return 'Interview complete — you can always add more anytime';
    if (state.conversation_status === 'discovery') return 'Discovery in progress';
    if (state.conversation_status === 'profiling') return 'Getting to know your role';
    if (state.onboarding_step === 'awaiting_consent') return 'Please review consent and reply YES to continue';
    return 'Getting started';
  }, [state, processingMedia, voiceUpload]);

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
          <div className="flex shrink-0 items-center gap-1">
            {canReadAloud && (
              <Button
                variant="ghost"
                size="sm"
                aria-pressed={readAloud.enabled}
                onClick={() => readAloud.setEnabled(!readAloud.enabled)}
                icon={readAloud.enabled ? <Volume2 className="h-4 w-4" /> : <VolumeX className="h-4 w-4" />}
              >
                <span className="hidden sm:inline">{readAloud.enabled ? 'Reading aloud' : 'Read aloud'}</span>
              </Button>
            )}
          <Button
            variant="ghost"
            size="sm"
            className="shrink-0"
            onClick={() => {
              readAloud.stop();
              clearDiscoverToken();
              navigate(`/discover/${token}`, { replace: true });
            }}
          >
            Sign out
          </Button>
          </div>
        </div>
      </header>

      <div className="mx-auto flex w-full max-w-3xl min-h-0 flex-1 flex-col px-3 py-3 sm:px-4">
        {(error || recorder.error) && (
          <p className="mb-2 shrink-0 rounded-md bg-destructive/10 px-3 py-2 text-sm text-destructive">
            {error || recorder.error}
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

            {recorder.recording ? (
              <div className="flex items-center gap-3 rounded-lg border border-destructive/30 bg-destructive/5 px-3 py-3">
                <span className="h-3 w-3 shrink-0 animate-pulse rounded-full bg-destructive" aria-hidden />
                <span className="text-sm font-medium text-foreground">
                  Recording {formatSeconds(recorder.seconds)}
                </span>
                <span className="hidden text-xs text-muted-foreground sm:inline">
                  Say your answer, then send it.
                </span>
                <div className="ml-auto flex gap-2">
                  <Button type="button" variant="ghost" onClick={recorder.cancel}>
                    Cancel
                  </Button>
                  <Button type="button" onClick={() => void sendRecording()} icon={<Send className="h-4 w-4" />}>
                    Send answer
                  </Button>
                </div>
              </div>
            ) : (
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

              {canRecord && (
                <Button
                  type="button"
                  variant="secondary"
                  disabled={!canAttach || sending || processingMedia}
                  onClick={() => void startRecording()}
                  aria-label="Answer out loud"
                  title={canAttach ? 'Answer out loud' : 'You can answer out loud once the interview starts'}
                  className="h-11 w-11 shrink-0 p-0"
                  icon={<Mic className="h-5 w-5" />}
                />
              )}

              <Button
                type="submit"
                disabled={sending || processingMedia || !canSend}
                className="h-11 shrink-0 px-4 sm:px-5"
              >
                Send
              </Button>
            </div>
            )}
            <p className="mt-2 hidden text-xs text-muted-foreground sm:block">
              Enter to send · Shift+Enter for a new line
              {canAttach && canRecord ? ' · Press the microphone to answer out loud' : ''}
              {canAttach ? ' · Attach images or PDFs during discovery' : ''}
            </p>
          </form>
        </div>
      </div>
    </div>
  );
}
