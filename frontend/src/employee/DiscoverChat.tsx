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
import { pendingSubmission, type PendingSubmission } from './pendingSubmission';

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
  const [processingMedia] = useState(false);
  const [voiceUpload, setVoiceUpload] = useState(false);
  const [uncertain, setUncertain] = useState(false);
  const [optimistic, setOptimistic] = useState<(PendingSubmission & { createdAt: string }) | null>(null);
  const [refreshNeeded, setRefreshNeeded] = useState(false);
  const pendingRef = useRef<PendingSubmission | null>(null);
  const latestVersion = useRef(-1);
  const reconcileBusy = useRef(false);
  const applySnapshot = useCallback((data: { messages: DiscoverMessage[]; state: DiscoverState }) => {
    const version = data.state.discovery_state_version;
    if (version !== undefined && version < latestVersion.current) return;
    if (version !== undefined) latestVersion.current = version;
    setRaw(data.messages);
    setState(data.state);
  }, []);

  const reconcileSubmission = useCallback(async (checkReceipt = true) => {
    const item = pendingRef.current;
    if (!jwt || !item || reconcileBusy.current) return;
    reconcileBusy.current = true;
    try {
      let data = checkReceipt ? await discoverApi.messages(jwt, item.id) : null;
      if (!data || data.state.submission_received !== true) {
        data = item.file ? await discoverApi.sendAttachment(jwt, item.file, item.body || undefined, item.id)
          : await discoverApi.sendMessage(jwt, item.body, item.id);
      }
      applySnapshot(data);
      setOptimistic(null);
      await pendingSubmission(token, null);
      pendingRef.current = null;
      setUncertain(false);
      setError('');
    } catch (err) {
      if ((err as { status?: number }).status === 409 || (err as { status?: number }).status === 422) {
        await pendingSubmission(token, { ...item, rejected: true });
        pendingRef.current = null;
        setOptimistic(null);
        setUncertain(false);
        setDraft(item.body);
        if (item.file) setSelectedFile(item.file);
        setError(err instanceof Error ? err.message : 'This answer was not accepted. Please review it before sending.');
        return;
      }
      setUncertain(true);
      setError('Your answer is saved on this device. Reconnecting to confirm delivery…');
    } finally { reconcileBusy.current = false; }
  }, [jwt, token, applySnapshot]);

  useEffect(() => {
    let active = true;
    void pendingSubmission(token).then(item => {
      if (!active || !item) return;
      if (item.rejected) {
        setDraft(item.body);
        if (item.file) setSelectedFile(item.file);
        return;
      }
      pendingRef.current = item;
      setOptimistic({ ...item, createdAt: new Date().toISOString() });
      setUncertain(true);
      void reconcileSubmission();
    }).catch(() => { /* Sending will report unavailable durable device storage. */ });
    return () => { active = false; };
  }, [token, reconcileSubmission]);

  useEffect(() => {
    if (!uncertain) return;
    const timer = window.setInterval(() => void reconcileSubmission(), 3000);
    return () => window.clearInterval(timer);
  }, [uncertain, reconcileSubmission]);

  useEffect(() => {
    if (!refreshNeeded || !jwt) return;
    let active = true;
    let timer: number;
    const refresh = async () => {
      try {
        const data = await discoverApi.messages(jwt);
        if (!active) return;
        applySnapshot(data);
        setRefreshNeeded(false);
      } catch { if (active) timer = window.setTimeout(() => void refresh(), 3000); }
    };
    void refresh();
    return () => { active = false; window.clearTimeout(timer); };
  }, [refreshNeeded, jwt, applySnapshot]);

  const submitAnswer = async (body: string, file?: File) => {
    if (!jwt || pendingRef.current) return;
    const item = { id: crypto.randomUUID(), body, file };
    pendingRef.current = item;
    setOptimistic({ ...item, createdAt: new Date().toISOString() });
    try {
      await pendingSubmission(token, item);
    } catch {
      pendingRef.current = null;
      setOptimistic(null);
      setDraft(body);
      if (file) setSelectedFile(file);
      setError('Could not save your answer on this device. Please keep this page open and try again.');
      return;
    }
    // The first POST is ordinary delivery. Reconciliation is only needed after
    // an uncertain outcome or when restoring a saved submission after refresh.
    await reconcileSubmission(false);
  };

  const recorder = useVoiceRecorder();
  const readAloud = useReadAloud(jwt, state);
  // The newest interviewer message already heard (or already on screen when the
  // page opened), so each question is read out once, when it arrives.
  const lastSpokenRef = useRef<number | null>(null);

  const messages = useMemo(
    () =>
      mapMessages(optimistic && !raw.some(m => m.submission_id === optimistic.id)
        ? [...raw, { id: -1, direction: 'inbound', message_type: optimistic.file?.type.startsWith('audio/') ? 'audio' : 'text',
          body: optimistic.body || optimistic.file?.name || '', is_discovery_question: false, created_at: optimistic.createdAt }]
        : raw, {
        onPlay: (m) => void readAloud.speak(m.id, m.body),
        speakingId: readAloud.speakingId,
      }),
    [raw, optimistic, readAloud]
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
    applySnapshot(data);
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

  // Saved text answers recover through Sidekiq, just like media. Poll only the
  // read endpoint; never re-submit the employee's answer from the browser.
  useEffect(() => {
    if (!jwt || !state?.discovery_pending) return;
    let active = true;
    let timer: number;
    const poll = async () => {
      try {
        const data = await discoverApi.messages(jwt);
        if (!active) return;
        applySnapshot(data);
        if (!data.state.discovery_pending) return;
      } catch { /* Keep the saved answer; the next read may recover. */ }
      if (active) timer = window.setTimeout(() => void poll(), 3000);
    };
    timer = window.setTimeout(() => void poll(), 3000);
    return () => { active = false; window.clearTimeout(timer); };
  }, [jwt, state?.discovery_pending]);

  const send = async (e: React.FormEvent) => {
    e.preventDefault();
    // A failed answer the engine cannot process may be replaced by a rephrased text answer.
    const blockedByError = Boolean(state?.discovery_error && !(state?.can_rephrase && !selectedFile));
    if (!jwt || sending || uncertain || pendingRef.current || state?.discovery_pending || blockedByError) return;

    if (!selectedFile && !draft.trim()) return;
    const body = draft.trim();
    const file = selectedFile || undefined;
    setError('');
    setSending(true);
    setDraft('');
    setSelectedFile(null);
    try { await submitAnswer(body, file); }
    finally { setSending(false); }
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
      await submitAnswer('', file);
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
  // An answer the engine could not process may be rephrased instead of only retried.
  const canRephrase = Boolean(state?.discovery_error && state?.can_rephrase && !state?.discovery_pending);
  const awaitingRecovery = Boolean(uncertain || state?.discovery_pending || (state?.discovery_error && !canRephrase));
  const retrySavedAnswer = async () => {
    if (!jwt || sending) return;
    setSending(true);
    setError('');
    try {
      const data = await discoverApi.retryMessage(jwt);
      applySnapshot(data);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not retry your saved answer');
      setRefreshNeeded(true);
    } finally { setSending(false); }
  };
  const canRecord = Boolean(state?.voice?.recording) && voiceRecordingSupported();
  const canReadAloud =
    Boolean(state?.voice?.speech) || (typeof window !== 'undefined' && 'speechSynthesis' in window);

  const statusLabel = useMemo(() => {
    if (!state) return null;
    if (uncertain) return 'Your answer is saved on this device. Confirming delivery…';
    if (sending) return 'Sending your answer…';
    if (processingMedia) return voiceUpload ? 'Listening to your answer…' : 'Processing your file…';
    if (state.discovery_phase === 'processing') return 'Working on your saved answer…';
    if (state.discovery_phase === 'queued') return 'Your answer is saved. Getting ready…';
    if (state.discovery_pending) return 'Your answer is saved. Retrying shortly…';
    if (state.discovery_error && state.can_rephrase) return 'Your last answer could not be processed — retry it or rephrase it';
    if (state.discovery_error) return 'Your answer is saved — the interview is paused';
      if (state.interview_paused) return 'Interview paused — your answers are saved. Say “continue” when you are ready.';
      if (state.interview_phase && !state.completed) return ({ anchor: 'Your working day', inventory: 'Your regular and periodic work', invisible_work: 'Work behind the scenes', size_close: 'Effort estimates and your summary' })[state.interview_phase];
    if (state.completed && state.discovery_outcome === 'employee_stopped') return 'Interview stopped — your answers are saved';
    if (state.completed && state.discovery_outcome && state.discovery_outcome !== 'successful') return 'Answers saved — workflow details need follow-up';
    if (state.completed) return 'Interview complete — you can always add more anytime';
    if (state.conversation_status === 'discovery') return 'Discovery in progress';
    if (state.conversation_status === 'profiling') return 'Getting to know your role';
    if (state.onboarding_step === 'awaiting_consent') return 'Please review consent and reply YES to continue';
    return 'Getting started';
  }, [state, sending, processingMedia, voiceUpload, uncertain]);

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
            showTyping={processingMedia || state?.discovery_phase === 'processing'}
          />

          <form
            onSubmit={send}
            className="shrink-0 border-t border-border bg-background/95 px-3 py-3 backdrop-blur-sm sm:px-4 sm:py-4"
          >
            {state?.discovery_error && !state.discovery_pending && (
              <div className="mb-3 text-sm" role="status">
                <p>{canRephrase
                  ? 'Your answer is saved, but I could not process it. Retry it, or type your answer again in different words below.'
                  : 'Your answer is saved. Please contact your company administrator if the service remains unavailable.'}</p>
                <Button type="button" disabled={sending} onClick={() => void retrySavedAnswer()}>
                  Retry saved answer
                </Button>
              </div>
            )}
            {state?.completed && (
              <p className="mb-3 text-sm text-muted-foreground">
                  {state.discovery_outcome === 'employee_stopped' ? 'Your answers are saved. We stopped as you requested.'
                    : state.discovery_outcome && state.discovery_outcome !== 'successful'
                    ? 'Your answers are saved. Some details still need follow-up.'
                    : 'Interview complete — but you can always add more anytime.'}
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
                disabled={!canAttach || sending || processingMedia || awaitingRecovery}
                onChange={(e) => {
                  const file = e.target.files?.[0];
                  if (file) setSelectedFile(file);
                  e.target.value = '';
                }}
              />
              <Button
                type="button"
                variant="secondary"
                disabled={!canAttach || sending || processingMedia || awaitingRecovery}
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
                  disabled={sending || processingMedia || awaitingRecovery}
                  className="min-h-[72px] max-h-40 w-full resize-none text-base sm:min-h-[88px]"
                />
              </div>

              {canRecord && (
                <Button
                  type="button"
                  variant="secondary"
                  disabled={!canAttach || sending || processingMedia || awaitingRecovery}
                  onClick={() => void startRecording()}
                  aria-label="Answer out loud"
                  title={canAttach ? 'Answer out loud' : 'You can answer out loud once the interview starts'}
                  className="h-11 w-11 shrink-0 p-0"
                  icon={<Mic className="h-5 w-5" />}
                />
              )}

              <Button
                type="submit"
                disabled={sending || processingMedia || awaitingRecovery || !canSend}
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
