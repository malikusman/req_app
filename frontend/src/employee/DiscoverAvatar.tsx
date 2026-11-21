import { useCallback, useEffect, useRef, useState } from 'react';
import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { CheckCircle2, Clock, Keyboard, Mic, MicOff, Pause, PhoneOff, Play, RefreshCw, ShieldCheck, Waves } from 'lucide-react';
import { Button } from '../components/ui';
import { discoverApi, getStoredDiscoverToken, type DiscoverMessage, type DiscoverState, type VoiceSession } from './discoverApi';
import { LiveAvatarRenderer, endOfTurnMs, mergeSegment, spokenText } from './avatar/liveAvatar';

/**
 * Live AI-avatar interview with June (LiveAvatar FULL, restricted mode).
 *
 * LiveAvatar is June's face, voice and ears: it detects when the employee speaks,
 * transcribes them and says the text we send. Every question and decision comes
 * from the Employee Discovery V2 engine through the same durable message API as
 * the text interview (saved answers, recovery, read-back and confirmation).
 *
 * There is no other avatar and no silent fallback: if LiveAvatar cannot start or
 * drops, the page says so plainly and offers to retry. Answers are always saved.
 */
type Caption = { who: 'avatar' | 'you'; text: string; id: string };
type TurnState = 'idle' | 'listening' | 'hearing' | 'thinking' | 'speaking';
type Phase = 'start' | 'consent' | 'connecting' | 'live' | 'paused' | 'completed' | 'ended' | 'error';
type Failure = { title: string; reason: string; resume: boolean; retryable: boolean };
type TurnMetric = { turn: number; speechStoppedAt?: number; finalAt?: number; submittedAt?: number; ackFirstAudioAt?: number | null;
  replyAt?: number; questionFirstAudioAt?: number | null; words?: number };
type InterviewPhase = NonNullable<DiscoverState['interview_phase']>;

// End of turn: see endOfTurnMs (longer after a fragment or a sentence left open).
// A reply that arrives while the employee is still talking waits for them, up to this long.
const HOLD_QUESTION_MAX_MS = 15_000;
// The first question can still be being written when the page opens.
const FIRST_QUESTION_WAIT_MS = 45_000;
// Barge-in: June stops only for sustained speech, not a cough or an "mm".
const BARGE_IN_MS = 450;
// An interruption that produced no words: June asks her question again.
const REASK_AFTER_EMPTY_INTERRUPT_MS = 2500;
const BACKCHANNEL_DELAY_MS = 1800; // only if the next question is not ready by then
const STILL_WORKING_MS = 12_000;
const STALL_MS = 60_000; // then offer "keep waiting" / "try again"; never wait silently forever
const REQUEST_TIMEOUT_MS = 20_000;
// Starting up: a busy server can be slow to answer the first reads. Allow longer,
// and retry the (read-only) ones once, before showing an error.
const START_TIMEOUT_MS = 45_000;
const POLL_MS = 400;

const PHASES: { key: InterviewPhase; label: string }[] = [
  { key: 'anchor', label: 'Your day' },
  { key: 'inventory', label: 'Regular work' },
  { key: 'invisible_work', label: 'Hidden effort' },
  { key: 'size_close', label: 'Time & confirm' },
];

declare global { interface Window { __avatarMetrics?: TurnMetric[] } }

/** Resolves with the promise's value, or rejects after `ms` (the request may still complete). */
function withTimeout<T>(promise: Promise<T>, ms: number): Promise<T> {
  return new Promise((resolve, reject) => {
    const timer = window.setTimeout(() => reject(new Error('timeout')), ms);
    promise.then((v) => { window.clearTimeout(timer); resolve(v); }, (e) => { window.clearTimeout(timer); reject(e); });
  });
}

const reasonOf = (err: unknown) => (err instanceof Error && err.message !== 'timeout' ? err.message
  : 'The server took too long to respond. Please try again in a moment.');

/** A read-only request at start-up: one automatic retry after a timeout or network error. */
async function readWithRetry<T>(request: () => Promise<T>): Promise<T> {
  try {
    return await withTimeout(request(), START_TIMEOUT_MS);
  } catch (err) {
    if ((err as { status?: number }).status) throw err; // a real answer from the server: do not retry
    return withTimeout(request(), START_TIMEOUT_MS);
  }
}

/** Messages June speaks: interviewer messages, never WhatsApp onboarding copy. */
const speakable = (m: DiscoverMessage) => m.direction === 'outbound' && m.track !== 'onboarding' && Boolean(m.body.trim());

export function DiscoverAvatar() {
  const { token = '' } = useParams();
  const [search] = useSearchParams();
  const debug = search.get('debug') === '1';
  const navigate = useNavigate();
  const videoRef = useRef<HTMLVideoElement>(null);
  const captionsEnd = useRef<HTMLDivElement>(null);
  const avatar = useRef<LiveAvatarRenderer | null>(null);
  const texts = useRef<{ acknowledgements: string[]; phrases: Record<string, string> }>({ acknowledgements: [], phrases: {} });
  const lastAck = useRef(-1);
  const jwt = useRef<string | null>(null);
  const sessionStarted = useRef(false); // a LiveAvatar token was minted: the server must stop it
  const lastSeenId = useRef(0);
  const lastQuestion = useRef('');
  const pendingText = useRef<string[]>([]);
  const carryText = useRef<string[]>([]); // spoken while the previous answer was being processed
  // Only speech heard after June's latest question can end a turn: silence, noise
  // or held-over words alone never produce an answer (and so never a new question).
  const answerStarted = useRef(false);
  const replyArrived = useRef(false); // June is now asking the next question: speech is the next answer
  const waitingSubmission = useRef<string | null>(null);
  const submitTimer = useRef<number | null>(null);
  const bargeTimer = useRef<number | null>(null);
  const reaskTimer = useRef<number | null>(null);
  const busy = useRef(false);
  const paused = useRef(false);
  const muted = useRef(false);
  const micOpen = useRef(false);
  const avatarSpeaking = useRef(false);
  const userSpeaking = useRef(false);
  const interruptedQuestion = useRef(false); // this answer cut June's question short
  const metrics = useRef<TurnMetric[]>([]);
  const current = useRef<TurnMetric | null>(null);

  const [phase, setPhase] = useState<Phase>('start');
  const [name, setName] = useState('June');
  const [connected, setConnected] = useState(false);
  const [micState, setMicState] = useState<'off' | 'on' | 'muted'>('off');
  const [turn, setTurn] = useState<TurnState>('idle');
  const [captions, setCaptions] = useState<Caption[]>([]);
  const [live, setLive] = useState('');
  const [notice, setNotice] = useState('');
  const [failure, setFailure] = useState<Failure | null>(null);
  const [consent, setConsent] = useState<{ text: string; version: string } | null>(null);
  const [consenting, setConsenting] = useState(false);
  const [stalled, setStalled] = useState<'slow' | 'failed' | null>(null);
  const [showCaptions, setShowCaptions] = useState(true);
  const [interviewPhase, setInterviewPhase] = useState<InterviewPhase | null>(null);
  const [debugInfo, setDebugInfo] = useState('');
  const [metricLog, setMetricLog] = useState<TurnMetric[]>([]);

  const caption = useCallback((who: Caption['who'], text: string) => {
    setCaptions((list) => [...list.slice(-60), { who, text, id: `${Date.now()}-${Math.random()}` }]);
  }, []);

  useEffect(() => { captionsEnd.current?.scrollIntoView({ block: 'nearest' }); }, [captions, live]);

  const clearTimer = (ref: { current: number | null }) => {
    if (ref.current) { window.clearTimeout(ref.current); ref.current = null; }
  };

  const idleTurn = useCallback(() => {
    if (busy.current || userSpeaking.current || avatarSpeaking.current) return;
    setTurn(paused.current || !micOpen.current ? 'idle' : 'listening');
  }, []);

  /** LiveAvatar hears the employee except when paused or muted. */
  const listen = useCallback((on: boolean) => {
    micOpen.current = on && !paused.current && !muted.current;
    avatar.current?.setUserListening(micOpen.current);
    setMicState(!avatar.current ? 'off' : muted.current ? 'muted' : micOpen.current ? 'on' : 'off');
    idleTurn();
  }, [idleTurn]);

  /** June says a line (caption shown as written, spoken as the server normalises it). */
  const say = useCallback(async (text: string | undefined, showCaption = true) => {
    if (!text?.trim()) return null;
    if (showCaption) caption('avatar', text);
    const renderer = avatar.current;
    if (!renderer?.connected) return null;
    return renderer.say(spokenText(text));
  }, [caption]);

  const track = (state: DiscoverState) => { if (state.interview_phase) setInterviewPhase(state.interview_phase); };

  /** Speak every interviewer message the employee has not heard yet, in order. */
  const speakNew = useCallback(async (messages: DiscoverMessage[], silently = false) => {
    const fresh = messages.filter((m) => speakable(m) && m.id > lastSeenId.current);
    let firstAudio: number | null = null;
    for (const message of fresh) {
      lastSeenId.current = Math.max(lastSeenId.current, message.id);
      lastQuestion.current = message.body;
      if (silently) { caption('avatar', message.body); continue; }
      const result = await say(message.body);
      firstAudio ??= result?.firstAudioAt ?? null;
    }
    lastSeenId.current = Math.max(lastSeenId.current, ...messages.map((m) => m.id), 0);
    return firstAudio;
  }, [caption, say]);

  /** Ends the LiveAvatar session (and, as a backstop, asks the server to stop it). */
  const teardown = useCallback(async () => {
    [submitTimer, bargeTimer, reaskTimer].forEach(clearTimer);
    const renderer = avatar.current;
    avatar.current = null;
    micOpen.current = false;
    await renderer?.close();
    // Awaited, so a restart cannot race it. Stops idle billing if the tab closes.
    if (sessionStarted.current && jwt.current) await discoverApi.voiceSessionStop(jwt.current).catch(() => undefined);
    sessionStarted.current = false;
    setConnected(false);
    setMicState('off');
  }, []);

  const fail = useCallback(async (f: Failure) => {
    await teardown();
    busy.current = false;
    setTurn('idle');
    setFailure(f);
    setPhase('error');
  }, [teardown]);

  const finish = useCallback(async (state: DiscoverState) => {
    listen(false);
    setPhase('completed');
    if (state.discovery_outcome && state.discovery_outcome !== 'successful') {
      setNotice('Your answers are saved. A few details may need a short follow-up later.');
    }
    // June's closing words have been spoken (speakNew awaits them): end the session.
    window.setTimeout(() => { void teardown(); }, 1200);
  }, [listen, teardown]);

  /** A neutral backchannel, never the same one twice in a row. */
  const backchannel = useCallback(() => {
    const acks = texts.current.acknowledgements;
    if (!acks.length) return null;
    let index = Math.floor(Math.random() * acks.length);
    if (acks.length > 1 && index === lastAck.current) index = (index + 1) % acks.length;
    lastAck.current = index;
    return say(acks[index], false);
  }, [say]);

  /** Polls the durable turn until the engine replies; June then speaks the reply. */
  const waitForReply = useCallback(async (submissionId: string, metric: TurnMetric) => {
    if (!jwt.current) return;
    waitingSubmission.current = submissionId;
    setStalled(null);
    const started = performance.now();
    const ack: { spoken: ReturnType<typeof say> | null } = { spoken: null };
    const ackTimer = window.setTimeout(() => { if (!userSpeaking.current) ack.spoken = backchannel(); }, BACKCHANNEL_DELAY_MS);
    let saidStillWorking = false;
    let retried = false;
    try {
      for (;;) {
        await new Promise((r) => setTimeout(r, POLL_MS));
        if (!jwt.current || !avatar.current) return; // ended or failed meanwhile
        const snapshot = await withTimeout(discoverApi.messages(jwt.current, submissionId), REQUEST_TIMEOUT_MS).catch(() => null);
        if (snapshot) {
          const { messages, state } = snapshot;
          track(state);
          if (state.discovery_error && !state.discovery_pending) {
            if (state.can_rephrase) {
              // Saved but not usable (e.g. empty after transcription): ask again.
              window.clearTimeout(ackTimer);
              await say(texts.current.phrases.rephrase || 'Sorry, could you say that again?');
              break;
            }
            if (!retried) {
              // A transient engine failure: reprocess the saved answer once.
              retried = true;
              await withTimeout(discoverApi.retryMessage(jwt.current), REQUEST_TIMEOUT_MS).catch(() => undefined);
              continue;
            }
            window.clearTimeout(ackTimer);
            setStalled('failed');
            return;
          }
          const hasReply = messages.some((m) => speakable(m) && m.id > lastSeenId.current);
          if ((hasReply || state.completed) && !state.discovery_pending) {
            window.clearTimeout(ackTimer);
            metric.replyAt = performance.now();
            if (ack.spoken) metric.ackFirstAudioAt = (await ack.spoken)?.firstAudioAt ?? null;
            // The employee is still talking (they carried on after a pause): let them
            // finish, then ask. What they added is kept as the start of their next
            // answer, never sent on its own to a question they have not heard.
            const held = performance.now();
            while (userSpeaking.current && performance.now() - held < HOLD_QUESTION_MAX_MS) {
              await new Promise((r) => setTimeout(r, 200));
            }
            if (carryText.current.length) { pendingText.current = [...pendingText.current, ...carryText.current]; carryText.current = []; }
            replyArrived.current = true;
            metric.questionFirstAudioAt = await speakNew(messages);
            if (state.completed) await finish(state);
            break;
          }
        }
        const waited = performance.now() - started;
        if (!saidStillWorking && waited > STILL_WORKING_MS && !userSpeaking.current) {
          saidStillWorking = true;
          void say(texts.current.phrases.still_working, false);
        }
        if (waited > STALL_MS) {
          window.clearTimeout(ackTimer);
          setStalled('slow'); // the answer is saved; the employee chooses to keep waiting or retry
          return;
        }
      }
      waitingSubmission.current = null;
    } finally {
      window.clearTimeout(ackTimer);
    }
  }, [backchannel, finish, say, speakNew]);

  /** Sends one answer through the durable message API (idempotent retries) and waits for the reply. */
  const submit = useCallback(async () => {
    const text = pendingText.current.join(' ').replace(/\s+/g, ' ').trim();
    if (!text || !jwt.current || busy.current || paused.current || !answerStarted.current) return;
    pendingText.current = [];
    answerStarted.current = false;
    replyArrived.current = false;
    busy.current = true;
    clearTimer(reaskTimer);
    setTurn('thinking');
    setLive('');
    setNotice('');
    const metric = current.current ?? { turn: metrics.current.length + 1 };
    current.current = null;
    metric.submittedAt = performance.now();
    metric.words = text.split(' ').length;
    const submissionId = crypto.randomUUID();
    const interrupted = interruptedQuestion.current;
    interruptedQuestion.current = false;
    try {
      // The same submission id makes retries safe: the server records one answer.
      let accepted = false;
      for (let attempt = 0; attempt < 3 && !accepted; attempt += 1) {
        try {
          await withTimeout(discoverApi.sendMessage(jwt.current, text, submissionId, { interruptedQuestion: interrupted }), REQUEST_TIMEOUT_MS);
          accepted = true;
        } catch (err) {
          const check = await withTimeout(discoverApi.messages(jwt.current, submissionId), REQUEST_TIMEOUT_MS).catch(() => null);
          if (check?.state.submission_received) accepted = true;
          else if (attempt === 2) throw err;
        }
      }
      await waitForReply(submissionId, metric);
    } catch (err) {
      setNotice(`${reasonOf(err)} Your last answer did not reach us; please say it again.`);
    } finally {
      metrics.current.push(metric);
      window.__avatarMetrics = metrics.current;
      setMetricLog([...metrics.current]);
      busy.current = false;
      replyArrived.current = false;
      if (!paused.current && avatar.current) {
        // Words said while June was working open the next answer; it is sent once
        // the employee speaks again after hearing the question.
        if (carryText.current.length) { pendingText.current = [...pendingText.current, ...carryText.current]; carryText.current = []; }
        listen(true);
        // They answered while June was still asking: send it once they have finished.
        if (answerStarted.current && !userSpeaking.current) scheduleSubmit();
      }
    }
  }, [listen, waitForReply]); // eslint-disable-line react-hooks/exhaustive-deps -- scheduleSubmit is stable (refs only)

  /** Submit after a natural pause; longer when only a fragment has been heard. */
  function scheduleSubmit() {
    clearTimer(submitTimer);
    if (!answerStarted.current) return;
    const heard = pendingText.current.join(' ').trim();
    submitTimer.current = window.setTimeout(() => {
      submitTimer.current = null;
      if (!userSpeaking.current) void submit();
    }, endOfTurnMs(heard));
  }

  const bargeIn = () => {
    clearTimer(bargeTimer);
    if (!avatar.current?.isSpeaking) return;
    interruptedQuestion.current = true;
    avatar.current.interrupt();
  };

  const keepWaiting = () => {
    const id = waitingSubmission.current;
    setStalled(null);
    if (!id) return;
    busy.current = true;
    setTurn('thinking');
    void waitForReply(id, { turn: metrics.current.length + 1 }).finally(() => { busy.current = false; listen(true); });
  };

  const retryAnswer = async () => {
    if (!jwt.current) return;
    setStalled(null);
    await withTimeout(discoverApi.retryMessage(jwt.current), REQUEST_TIMEOUT_MS).catch(() => undefined);
    keepWaiting();
  };

  const start = useCallback(async (resume = false) => {
    jwt.current = getStoredDiscoverToken(token);
    if (!jwt.current) { navigate(`/discover/${token}`, { replace: true }); return; }
    setPhase('connecting');
    setFailure(null);
    setNotice('');
    setStalled(null);
    paused.current = false;
    pendingText.current = [];
    carryText.current = [];
    answerStarted.current = false;
    let session: VoiceSession;
    let messages: DiscoverMessage[];
    try {
      const auth = jwt.current;
      const snapshot = await readWithRetry(() => discoverApi.messages(auth));
      messages = snapshot.messages;
      track(snapshot.state);
      if (snapshot.state.completed) { setPhase('completed'); return; }
      if (snapshot.state.onboarding_step === 'awaiting_consent') {
        // Web consent first: no avatar session (and no credits) until the employee agrees.
        const terms = await readWithRetry(() => discoverApi.consent(auth));
        setConsent({ text: terms.text, version: terms.version });
        setPhase('consent');
        return;
      }
      session = await withTimeout(discoverApi.voiceSession(auth), START_TIMEOUT_MS);
    } catch (err) {
      // 409: the interview is no longer open (e.g. already completed elsewhere).
      await fail({ title: `${name} couldn't connect`, reason: reasonOf(err), resume, retryable: (err as { status?: number }).status !== 409 });
      return;
    }
    texts.current = session.texts ?? { acknowledgements: [], phrases: {} };
    setName(session.display_name || 'June');
    setDebugInfo(`LiveAvatar ${session.liveavatar.mode}${session.liveavatar.sandbox ? ' (sandbox)' : ''}`);
    sessionStarted.current = true;
    const renderer = new LiveAvatarRenderer({
      onSpeaking: (speaking) => {
        avatarSpeaking.current = speaking;
        if (speaking) setTurn('speaking');
        else idleTurn();
      },
      onDisconnected: (reason) => {
        void fail({ title: `The connection to ${session.display_name || 'June'} was lost`, reason, resume: true, retryable: true });
      },
      onUserSpeechStarted: () => {
        clearTimer(submitTimer);
        clearTimer(reaskTimer);
        userSpeaking.current = true;
        setTurn('hearing');
        if (avatar.current?.isSpeaking) bargeTimer.current = window.setTimeout(bargeIn, BARGE_IN_MS);
      },
      onUserSpeechStopped: () => {
        userSpeaking.current = false;
        clearTimer(bargeTimer);
        current.current ??= { turn: metrics.current.length + 1 };
        current.current.speechStoppedAt = performance.now();
        if (!busy.current && answerStarted.current) scheduleSubmit();
        else idleTurn();
        if (interruptedQuestion.current && !busy.current && !answerStarted.current) {
          // June stopped for them but no words came through: ask again, once.
          reaskTimer.current = window.setTimeout(() => {
            reaskTimer.current = null;
            if (busy.current || userSpeaking.current || answerStarted.current || !interruptedQuestion.current) return;
            interruptedQuestion.current = false;
            void say(lastQuestion.current, false);
          }, REASK_AFTER_EMPTY_INTERRUPT_MS);
        }
      },
      onUserPartial: (text) => setLive(text),
      onUserFinal: (text) => {
        if (paused.current) return;
        clearTimer(reaskTimer);
        // A short answer said over June ("yes", "weekly") still counts as a barge-in.
        if (avatar.current?.isSpeaking) bargeIn();
        caption('you', text);
        setLive('');
        if (busy.current && !replyArrived.current) { carryText.current = mergeSegment(carryText.current, text); return; } // kept for the next answer
        current.current ??= { turn: metrics.current.length + 1 };
        current.current.finalAt = performance.now();
        pendingText.current = mergeSegment(pendingText.current, text);
        answerStarted.current = true;
        if (!userSpeaking.current) scheduleSubmit();
      },
      onUnexpectedSpeech: (detail) => {
        console.warn('[avatar] LiveAvatar guard:', detail);
        if (debug) setNotice(`Guard: ${detail}. It was silenced.`);
      },
      onEchoDropped: (text) => { if (debug) console.info('[avatar] dropped echo of June:', text); },
    });
    try {
      if (!videoRef.current) throw new Error('video element missing');
      await renderer.connect(session.liveavatar.session_token, videoRef.current);
    } catch (err) {
      await fail({ title: `${session.display_name || 'June'} couldn't connect`, reason: reasonOf(err), resume, retryable: true });
      return;
    }
    avatar.current = renderer;
    setConnected(true);
    setPhase('live');
    // Greet (microphone closed, so "hello" is not taken as an answer), then ask
    // whatever the interview is waiting on and open the microphone.
    const lastInbound = Math.max(0, ...messages.filter((m) => m.direction === 'inbound').map((m) => m.id));
    lastSeenId.current = lastInbound;
    const pendingQuestion = messages.filter((m) => speakable(m) && m.id > lastInbound).at(-1)
      ?? messages.filter(speakable).at(-1);
    if (pendingQuestion) lastQuestion.current = pendingQuestion.body;
    listen(false);
    await say(resume ? texts.current.phrases.resumed : texts.current.phrases.greeting);
    if (!avatar.current) return;
    let latest = messages;
    if (!latest.some((m) => speakable(m) && m.id > lastInbound)) {
      // The first question is still being written (e.g. just after consent): wait
      // for it rather than leaving June silent. Nothing is submitted meanwhile.
      setTurn('thinking');
      const since = performance.now();
      while (avatar.current && jwt.current && performance.now() - since < FIRST_QUESTION_WAIT_MS) {
        await new Promise((r) => setTimeout(r, 1000));
        const snapshot = await withTimeout(discoverApi.messages(jwt.current), REQUEST_TIMEOUT_MS).catch(() => null);
        if (snapshot?.messages.some((m) => speakable(m) && m.id > lastInbound)) { latest = snapshot.messages; break; }
      }
      idleTurn();
    }
    if (!avatar.current) return;
    listen(true);
    await speakNew(latest);
  }, [caption, debug, fail, idleTurn, listen, name, navigate, say, speakNew, token]); // eslint-disable-line react-hooks/exhaustive-deps -- scheduleSubmit/bargeIn are stable (refs only)

  const acceptConsent = async () => {
    if (!jwt.current || !consent) return;
    setConsenting(true);
    try {
      await withTimeout(discoverApi.acceptConsent(jwt.current, consent.version), START_TIMEOUT_MS);
      setConsent(null);
      await start();
    } catch (err) {
      await fail({ title: 'Your agreement could not be recorded', reason: reasonOf(err), resume: false, retryable: true });
    } finally {
      setConsenting(false);
    }
  };

  const togglePause = () => {
    if (phase === 'paused') {
      paused.current = false;
      setPhase('live');
      void (async () => {
        await say(texts.current.phrases.resumed);
        listen(true);
        if (lastQuestion.current) await say(lastQuestion.current, false);
      })();
    } else {
      paused.current = true;
      [submitTimer, bargeTimer, reaskTimer].forEach(clearTimer);
      avatar.current?.interrupt();
      listen(false);
      setTurn('idle');
      setPhase('paused');
    }
  };

  const toggleMute = () => {
    muted.current = !muted.current;
    listen(!paused.current);
  };

  /** The text interview, same employee session and saved conversation: it only reads, never re-sends. */
  const continueWithText = async () => {
    await teardown();
    navigate(`/discover/${token}/chat`);
  };

  const end = useCallback(async () => {
    await teardown();
    setTurn('idle');
    setPhase((p) => (p === 'completed' ? p : 'ended'));
  }, [teardown]);

  // Leaving the page or closing the tab ends the live avatar session.
  useEffect(() => {
    const leave = () => {
      void avatar.current?.close();
      avatar.current = null;
      if (sessionStarted.current && jwt.current) void discoverApi.voiceSessionStop(jwt.current);
      sessionStarted.current = false;
    };
    window.addEventListener('pagehide', leave);
    return () => { window.removeEventListener('pagehide', leave); leave(); };
  }, []);

  const inCall = phase === 'live' || phase === 'paused';
  const turnLabel = { idle: phase === 'paused' ? 'Paused' : '', listening: 'Listening', hearing: 'Listening to you…',
    thinking: `${name} is thinking`, speaking: `${name} is speaking` }[turn];
  const phaseIndex = interviewPhase ? PHASES.findIndex((p) => p.key === interviewPhase) : -1;

  return (
    <div className="flex min-h-screen flex-col bg-gradient-to-b from-muted/40 to-background text-foreground">
      <header className="flex flex-wrap items-center justify-between gap-3 border-b border-border bg-background/80 px-4 py-3 backdrop-blur sm:px-6">
        <div className="min-w-0">
          <div className="text-xs font-medium uppercase tracking-wider text-muted-foreground">MJaDi work discovery</div>
          <div className="truncate font-semibold">Conversation with {name}</div>
        </div>
        <div className="flex flex-wrap items-center gap-2 text-xs" aria-live="polite">
          <span className="inline-flex items-center gap-1.5 rounded-full border border-border px-2.5 py-1" data-testid="avatar-status">
            <span className={`h-2 w-2 rounded-full ${connected ? 'bg-emerald-500' : phase === 'connecting' ? 'animate-pulse bg-amber-400' : 'bg-muted-foreground/40'}`} />
            {connected ? 'Connected' : phase === 'connecting' ? 'Connecting' : 'Not connected'}
            {debug && debugInfo && <span className="text-muted-foreground" data-testid="avatar-provider">({debugInfo})</span>}
          </span>
          <span className="inline-flex items-center gap-1.5 rounded-full border border-border px-2.5 py-1" data-testid="mic-status">
            {micState === 'on' ? <Mic className="h-3.5 w-3.5" /> : <MicOff className="h-3.5 w-3.5" />}
            {{ on: 'Microphone on', muted: 'Muted', off: 'Microphone off' }[micState]}
          </span>
        </div>
      </header>

      {inCall && (
        <nav className="border-b border-border bg-background/60 px-4 py-2 sm:px-6" aria-label="Interview progress" data-testid="phase-progress">
          <ol className="mx-auto flex max-w-6xl items-center gap-2 overflow-x-auto text-xs">
            {PHASES.map((p, i) => (
              <li key={p.key} className="flex shrink-0 items-center gap-2">
                <span className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 ${i === phaseIndex ? 'bg-primary text-primary-foreground'
                  : i < phaseIndex ? 'text-foreground' : 'text-muted-foreground'}`} aria-current={i === phaseIndex ? 'step' : undefined}>
                  {i < phaseIndex ? <CheckCircle2 className="h-3.5 w-3.5" /> : <span className="tabular-nums">{i + 1}</span>}
                  {p.label}
                </span>
                {i < PHASES.length - 1 && <span className="h-px w-4 bg-border" aria-hidden />}
              </li>
            ))}
          </ol>
        </nav>
      )}

      <main className="mx-auto grid w-full max-w-6xl flex-1 gap-5 px-4 py-5 sm:px-6 lg:grid-cols-[minmax(0,1fr)_340px]">
        <section className="flex min-w-0 flex-col gap-4">
          <div className="relative aspect-video w-full overflow-hidden rounded-2xl bg-slate-900 shadow-lg ring-1 ring-black/5">
            <video ref={videoRef} autoPlay playsInline className={`h-full w-full object-cover transition-opacity duration-500 ${connected ? 'opacity-100' : 'opacity-0'}`}
              data-testid="avatar-video" />
            {!connected && (
              <div className="absolute inset-0 flex flex-col items-center justify-center gap-3 px-6 text-center text-slate-200">
                <div className={`flex h-20 w-20 items-center justify-center rounded-full bg-slate-700 text-3xl font-semibold ${phase === 'connecting' ? 'animate-pulse' : ''}`}>
                  {name.slice(0, 1)}
                </div>
                <p className="text-sm text-slate-300">
                  {phase === 'connecting' ? `Connecting to ${name}…` : phase === 'completed' ? 'Conversation complete'
                    : phase === 'ended' ? 'Conversation paused' : phase === 'error' ? 'Not connected' : `${name} will join when you start`}
                </p>
              </div>
            )}
            {connected && (
              <div className="absolute left-3 top-3 rounded-full bg-black/50 px-3 py-1 text-xs font-medium text-white backdrop-blur">
                {name} · AI interviewer
              </div>
            )}
            {inCall && turnLabel && (
              <div className="absolute bottom-3 left-1/2 flex -translate-x-1/2 items-center gap-2 rounded-full bg-background/90 px-4 py-1.5 text-sm shadow"
                data-testid="turn-status" data-state={turn}>
                {turn === 'thinking' ? (
                  <span className="flex gap-1" aria-hidden>
                    {[0, 1, 2].map((i) => <span key={i} className="h-1.5 w-1.5 animate-bounce rounded-full bg-muted-foreground" style={{ animationDelay: `${i * 150}ms` }} />)}
                  </span>
                ) : turn === 'speaking' ? <Waves className="h-4 w-4 text-primary" aria-hidden />
                  : (turn === 'listening' || turn === 'hearing') && <span className={`h-2 w-2 rounded-full bg-emerald-500 ${turn === 'hearing' ? 'animate-ping' : ''}`} aria-hidden />}
                <span className={turn === 'thinking' ? 'sr-only sm:not-sr-only' : ''}>{turnLabel}</span>
              </div>
            )}
          </div>

          {inCall && (
            <div className="flex flex-wrap justify-center gap-2">
              {phase !== 'paused' && (
                <Button variant="secondary" onClick={togglePause} data-testid="avatar-pause"><Pause className="mr-1 h-4 w-4" />Pause</Button>
              )}
              <Button variant="secondary" onClick={toggleMute} data-testid="avatar-mute" disabled={phase === 'paused'}>
                {micState === 'muted' ? <><Mic className="mr-1 h-4 w-4" />Unmute</> : <><MicOff className="mr-1 h-4 w-4" />Mute</>}
              </Button>
              <Button variant="danger" onClick={() => void end()} data-testid="avatar-end"><PhoneOff className="mr-1 h-4 w-4" />End</Button>
            </div>
          )}

          {phase === 'paused' && (
            <section className="mx-auto flex w-full max-w-xl flex-col items-center gap-3 rounded-2xl border border-border bg-background p-6 text-center shadow-sm" data-testid="avatar-paused">
              <h2 className="text-base font-semibold">Conversation paused</h2>
              <p className="text-sm text-muted-foreground">Your answers so far are saved. Carry on with {name}, or switch to typing and pick up at the same question.</p>
              <div className="flex flex-wrap justify-center gap-2">
                <Button onClick={togglePause} data-testid="avatar-continue-avatar"><Play className="mr-1 h-4 w-4" />Continue with AI Avatar</Button>
                <Button variant="secondary" onClick={() => void continueWithText()} data-testid="avatar-continue-text"><Keyboard className="mr-1 h-4 w-4" />Continue with Text</Button>
              </div>
            </section>
          )}

          {notice && <p className="rounded-lg bg-muted px-3 py-2 text-center text-sm" role="status">{notice}</p>}

          {stalled && inCall && (
            <div className="flex flex-col items-center gap-3 rounded-xl border border-border bg-background p-4 text-center" role="alert" data-testid="avatar-stalled">
              <p className="text-sm">{stalled === 'failed' ? `${name} couldn't process your last answer. It is saved; you can try again.`
                : 'This is taking longer than usual. Your answer is saved.'}</p>
              <div className="flex flex-wrap justify-center gap-2">
                <Button onClick={() => void retryAnswer()} data-testid="avatar-retry-answer"><RefreshCw className="mr-1 h-4 w-4" />Try again</Button>
                {stalled === 'slow' && <Button variant="secondary" onClick={keepWaiting}>Keep waiting</Button>}
              </div>
            </div>
          )}

          {phase === 'start' && (
            <section className="mx-auto flex w-full max-w-xl flex-col gap-4 rounded-2xl border border-border bg-background p-6 shadow-sm">
              <div>
                <h1 className="text-xl font-semibold">Talk through your work with {name}</h1>
                <p className="mt-1 text-sm text-muted-foreground">
                  {name} is an AI interviewer. She'll ask about the work you actually do, listen, and follow up just like a colleague would.
                </p>
              </div>
              <ul className="grid gap-2 text-sm">
                <li className="flex gap-2"><Clock className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" />Usually 10 to 20 minutes. You can pause at any time.</li>
                <li className="flex gap-2"><Mic className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" />Just talk naturally. You can interrupt her whenever you like.</li>
                <li className="flex gap-2"><ShieldCheck className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" />Every answer is saved as you go, and you'll confirm the summary at the end.</li>
              </ul>
              <div className="flex flex-wrap items-center gap-3">
                <Button onClick={() => void start()} data-testid="avatar-start">Start the conversation</Button>
                <Link className="text-sm text-muted-foreground underline" to={`/discover/${token}/chat`}>Prefer typing?</Link>
              </div>
              <p className="text-xs text-muted-foreground">Use headphones or a quiet room for the best experience. Your browser will ask for the microphone.</p>
            </section>
          )}

          {phase === 'consent' && consent && (
            <section className="mx-auto flex w-full max-w-xl flex-col gap-4 rounded-2xl border border-border bg-background p-6 shadow-sm" data-testid="avatar-consent" aria-label="Before we start">
              <h2 className="text-base font-semibold">Before we start</h2>
              <p className="text-sm leading-relaxed text-muted-foreground">{consent.text}</p>
              <div className="flex flex-wrap gap-2">
                <Button onClick={() => void acceptConsent()} disabled={consenting} data-testid="avatar-consent-accept">
                  {consenting ? 'Starting…' : 'I agree, start the conversation'}
                </Button>
                <Button variant="secondary" onClick={() => navigate(`/discover/${token}`)}>Not now</Button>
              </div>
            </section>
          )}

          {phase === 'error' && failure && (
            <section className="mx-auto flex w-full max-w-xl flex-col gap-3 rounded-2xl border border-destructive/40 bg-background p-6 shadow-sm" role="alert" data-testid="avatar-error">
              <h2 className="text-base font-semibold">{failure.title}</h2>
              <p className="break-words text-sm text-muted-foreground" data-testid="avatar-error-reason">{failure.reason}</p>
              <p className="text-sm">Your answers so far are saved.</p>
              <div className="flex flex-wrap items-center gap-3">
                {failure.retryable && (
                  <Button onClick={() => void start(failure.resume)} data-testid="avatar-retry"><RefreshCw className="mr-1 h-4 w-4" />Try again</Button>
                )}
                <Link className="inline-flex items-center gap-1 text-sm text-muted-foreground underline" to={`/discover/${token}/chat`}>
                  <Keyboard className="h-4 w-4" />Continue by typing instead
                </Link>
              </div>
            </section>
          )}

          {(phase === 'ended' || phase === 'completed') && (
            <section className="mx-auto flex w-full max-w-xl flex-col items-center gap-3 rounded-2xl border border-border bg-background p-6 text-center shadow-sm" data-testid="avatar-finished">
              {phase === 'completed' && <CheckCircle2 className="h-8 w-8 text-emerald-500" aria-hidden />}
              <h2 className="text-base font-semibold">{phase === 'completed' ? 'Thank you, the conversation is complete' : 'Conversation paused'}</h2>
              <p className="text-sm text-muted-foreground">{phase === 'completed' ? 'Your answers and confirmation are saved. You can close this page.'
                : 'Your answers so far are saved. Pick up where you left off whenever you are ready.'}</p>
              {phase === 'ended' && (
                <div className="flex flex-wrap justify-center gap-2">
                  <Button onClick={() => void start(true)} data-testid="avatar-continue-avatar"><Play className="mr-1 h-4 w-4" />Continue with AI Avatar</Button>
                  <Button variant="secondary" onClick={() => void continueWithText()} data-testid="avatar-continue-text"><Keyboard className="mr-1 h-4 w-4" />Continue with Text</Button>
                </div>
              )}
            </section>
          )}
        </section>

        <aside className="flex min-h-[16rem] flex-col overflow-hidden rounded-2xl border border-border bg-background shadow-sm lg:max-h-[calc(100vh-11rem)]" aria-label="Conversation">
          <div className="flex items-center justify-between border-b border-border px-4 py-2.5">
            <h2 className="text-sm font-semibold">Conversation</h2>
            <button type="button" className="text-xs text-muted-foreground underline" onClick={() => setShowCaptions((v) => !v)}>
              {showCaptions ? 'Hide' : 'Show'} captions
            </button>
          </div>
          {showCaptions ? (
            <div className="flex flex-1 flex-col gap-3 overflow-y-auto p-4 text-sm" data-testid="captions">
              {!captions.length && !live && <p className="text-muted-foreground">What you and {name} say will appear here.</p>}
              {captions.map((c) => (
                <div key={c.id} className={`flex flex-col ${c.who === 'you' ? 'items-end' : 'items-start'}`}>
                  <span className="mb-0.5 text-[11px] uppercase tracking-wide text-muted-foreground">{c.who === 'you' ? 'You' : name}</span>
                  <p className={`max-w-[90%] whitespace-pre-line rounded-2xl px-3 py-2 ${c.who === 'you' ? 'bg-primary text-primary-foreground' : 'bg-muted'}`}>{c.text}</p>
                </div>
              ))}
              {live && <p className="self-end italic text-muted-foreground">{live}</p>}
              <div ref={captionsEnd} />
            </div>
          ) : (
            <p className="p-4 text-sm text-muted-foreground">Captions are hidden.</p>
          )}
        </aside>

        {debug && metricLog.length > 0 && (
          <pre className="overflow-x-auto rounded-md bg-muted p-2 text-xs lg:col-span-2" data-testid="avatar-metrics">
            {metricLog.map((m) => `turn ${m.turn}: speech-end→final ${ms(m.finalAt, m.speechStoppedAt)} · final→submit ${ms(m.submittedAt, m.finalAt)} · submit→backchannel ${ms(m.ackFirstAudioAt, m.submittedAt)} · submit→engine reply ${ms(m.replyAt, m.submittedAt)} · speech-end→next question audio ${ms(m.questionFirstAudioAt, m.speechStoppedAt)}`).join('\n')}
          </pre>
        )}
      </main>
    </div>
  );
}

function ms(a?: number | null, b?: number | null) {
  return a && b ? `${Math.round(a - b)} ms` : '–';
}
