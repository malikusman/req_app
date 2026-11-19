import { useCallback, useEffect, useRef, useState } from 'react';
import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { Captions, Mic, MicOff, Pause, Play, PhoneOff, RefreshCw, Wifi, WifiOff } from 'lucide-react';
import { Button } from '../components/ui';
import { discoverApi, getStoredDiscoverToken, type DiscoverMessage, type DiscoverState } from './discoverApi';
import { AvatarVoice } from './avatar/avatarVoice';
import { RealtimeStt, type SttHandlers } from './avatar/realtimeStt';

/**
 * Live AI-avatar interview. Every question and every decision comes from the
 * Employee Discovery V2 engine through the same durable message API as the text
 * interview (saved answers, recovery, read-back and confirmation). This page only
 * adds a face, a voice, live transcription and automatic turn-taking.
 */
type Caption = { who: 'avatar' | 'you'; text: string; id: string };
type TurnState = 'idle' | 'listening' | 'hearing' | 'thinking' | 'speaking';
type TurnMetric = { turn: number; speechStoppedAt?: number; finalAt?: number; submittedAt?: number; ackFirstAudioAt?: number | null;
  replyAt?: number; questionFirstAudioAt?: number | null; words?: number };

const SUBMIT_GRACE_MS = 900; // a short pause after the final words before submitting
const POLL_MS = 500;
const REPLY_TIMEOUT_MS = 150_000;

declare global { interface Window { __avatarMetrics?: TurnMetric[] } }

export function DiscoverAvatar() {
  const { token = '' } = useParams();
  const [search] = useSearchParams();
  const debug = search.get('debug') === '1';
  const navigate = useNavigate();
  const videoRef = useRef<HTMLVideoElement>(null);
  const audioRef = useRef<HTMLAudioElement>(null);
  const voice = useRef(new AvatarVoice());
  const stt = useRef<RealtimeStt | null>(null);
  const jwt = useRef<string | null>(null);
  const lastSeenId = useRef(0);
  const lastQuestionId = useRef<number | null>(null);
  const pendingText = useRef<string[]>([]);
  const submitTimer = useRef<number | null>(null);
  const busy = useRef(false);
  const paused = useRef(false);
  const muted = useRef(false);
  const avatarSpeaking = useRef(false);
  const metrics = useRef<TurnMetric[]>([]);
  const current = useRef<TurnMetric | null>(null);

  const [phase, setPhase] = useState<'start' | 'connecting' | 'live' | 'paused' | 'completed' | 'ended' | 'error'>('start');
  const [avatarStatus, setAvatarStatus] = useState<'connecting' | 'connected' | 'audio-only' | 'off'>('off');
  const [micStatus, setMicStatus] = useState<'off' | 'connecting' | 'listening' | 'muted' | 'denied' | 'failed'>('off');
  const [turn, setTurn] = useState<TurnState>('idle');
  const [captions, setCaptions] = useState<Caption[]>([]);
  const [live, setLive] = useState('');
  const [notice, setNotice] = useState('');
  const [error, setError] = useState('');
  const [showCaptions, setShowCaptions] = useState(true);
  const [fallback, setFallback] = useState('');
  const [, setMetricVersion] = useState(0);

  const caption = useCallback((who: Caption['who'], text: string) => {
    setCaptions((list) => [...list.slice(-30), { who, text, id: `${Date.now()}-${Math.random()}` }]);
  }, []);

  const listen = useCallback((on: boolean) => {
    const live = on && !paused.current && !muted.current;
    stt.current?.setListening(live);
    setMicStatus((s) => (s === 'denied' || s === 'failed' || s === 'off' ? s : muted.current ? 'muted' : 'listening'));
    if (live) setTurn('listening');
  }, []);

  const say = useCallback(async (target: Parameters<typeof discoverApi.voiceSpeechUrl>[0], text?: string) => {
    if (!jwt.current) return null;
    if (text) caption('avatar', text);
    try {
      return await voice.current.speak(discoverApi.voiceSpeechUrl(target), jwt.current);
    } catch {
      setNotice('The voice could not play this line; the words are shown below.');
      return null;
    }
  }, [caption]);

  /** Speak every interviewer message the employee has not heard yet, in order. */
  const speakNew = useCallback(async (messages: DiscoverMessage[]) => {
    const fresh = messages.filter((m) => m.direction === 'outbound' && m.id > lastSeenId.current && m.body.trim());
    let firstAudio: number | null = null;
    for (const message of fresh) {
      lastSeenId.current = Math.max(lastSeenId.current, message.id);
      lastQuestionId.current = message.id;
      const result = await say({ messageId: message.id }, message.body);
      firstAudio ??= result?.firstAudioAt ?? null;
    }
    lastSeenId.current = Math.max(lastSeenId.current, ...messages.map((m) => m.id), 0);
    return firstAudio;
  }, [say]);

  const finish = useCallback(async (state: DiscoverState) => {
    setPhase('completed');
    listen(false);
    caption('avatar', state.discovery_outcome === 'successful' || !state.discovery_outcome
      ? 'Your answers and confirmation are saved. Thank you.' : 'Your answers are saved. Some details still need follow-up.');
    // Let the avatar finish its closing words, then end the session (no idle billing).
    window.setTimeout(() => { stt.current?.close(); void voice.current.close(); }, 8000);
  }, [caption, listen]);

  /** Sends one answer through the durable message API and speaks the engine's reply. */
  const submit = useCallback(async () => {
    const text = pendingText.current.join(' ').replace(/\s+/g, ' ').trim();
    pendingText.current = [];
    if (!text || !jwt.current || busy.current) return;
    busy.current = true;
    listen(false); // one answer at a time; the durable API accepts one pending answer
    setTurn('thinking');
    setLive('');
    const metric = current.current ?? { turn: metrics.current.length + 1 };
    current.current = null;
    metric.submittedAt = performance.now();
    metric.words = text.split(' ').length;
    const submissionId = crypto.randomUUID();
    const ack = say({ acknowledgement: metric.turn % 4 });
    try {
      await discoverApi.sendMessage(jwt.current, text, submissionId);
      const started = performance.now();
      let saidStillWorking = false;
      for (;;) {
        await new Promise((r) => setTimeout(r, POLL_MS));
        const { messages, state } = await discoverApi.messages(jwt.current, submissionId);
        const hasReply = messages.some((m) => m.direction === 'outbound' && m.id > lastSeenId.current);
        if (state.discovery_error && !state.discovery_pending) {
          // The answer is saved but could not be processed: ask to rephrase (the
          // next answer supersedes it) or fall back to retrying it.
          if (state.can_rephrase) await say({ phrase: 'rephrase' }, 'Sorry, I could not record that properly. Could you say it again in different words?');
          else setNotice('Your answer is saved but could not be processed yet. You can retry from the text interview.');
          break;
        }
        if (hasReply && !state.discovery_pending) {
          metric.replyAt = performance.now();
          metric.ackFirstAudioAt = (await ack)?.firstAudioAt ?? null;
          metric.questionFirstAudioAt = await speakNew(messages);
          if (state.completed) await finish(state);
          break;
        }
        if (!saidStillWorking && performance.now() - started > 12_000) {
          saidStillWorking = true;
          void say({ phrase: 'still_working' });
        }
        if (performance.now() - started > REPLY_TIMEOUT_MS) {
          setNotice('This is taking longer than usual. Your answer is saved; you can continue in the text interview.');
          break;
        }
      }
    } catch (err) {
      setNotice(err instanceof Error ? err.message : 'Could not send your answer. It is not lost: please say it again.');
    } finally {
      metrics.current.push(metric);
      window.__avatarMetrics = metrics.current;
      setMetricVersion((v) => v + 1);
      busy.current = false;
      if (!paused.current) listen(true);
    }
  }, [finish, listen, say, speakNew]);

  /** Stop the session's media without leaving the page. */
  const teardown = useCallback(async () => {
    stt.current?.close();
    stt.current = null;
    await voice.current.close();
  }, []);

  const start = useCallback(async () => {
    jwt.current = getStoredDiscoverToken(token);
    if (!jwt.current) { navigate(`/discover/${token}`, { replace: true }); return; }
    setPhase('connecting');
    setError('');
    setFallback('');
    try {
      const { messages, state } = await discoverApi.messages(jwt.current);
      if (state.completed) { setPhase('completed'); caption('avatar', 'This interview is already complete. Thank you.'); return; }
      const session = await discoverApi.voiceSession(jwt.current);
      // Face first: the employee sees who they are talking to.
      setAvatarStatus('connecting');
      voice.current = new AvatarVoice(); // fresh per start: the previous one may have been closed
      voice.current.onSpeaking = (speaking) => {
        avatarSpeaking.current = speaking;
        if (speaking) setTurn('speaking'); else if (!busy.current) setTurn(paused.current ? 'idle' : 'listening');
      };
      voice.current.onDisconnected = (reason) => {
        setAvatarStatus('audio-only');
        voice.current.useAudioOnly();
        setNotice(`Avatar disconnected (${reason}). Continuing with voice only. You can reconnect.`);
      };
      if (session.simli && videoRef.current && audioRef.current) {
        try {
          await voice.current.connectAvatar(session.simli.session_token, videoRef.current, audioRef.current);
          setAvatarStatus('connected');
        } catch (err) {
          voice.current.useAudioOnly();
          setAvatarStatus('audio-only');
          setNotice(`The avatar could not connect (${err instanceof Error ? err.message : 'unknown error'}). Continuing with voice only.`);
        }
      } else {
        voice.current.useAudioOnly();
        setAvatarStatus('audio-only');
        setNotice(session.simli_error ? 'The avatar is unavailable right now. Continuing with voice only.' : '');
      }
      setMicStatus('connecting');
      const handlers: SttHandlers = {
        onSpeechStarted: () => {
          if (submitTimer.current) { window.clearTimeout(submitTimer.current); submitTimer.current = null; }
          // Barge-in: the employee is answering; stop the avatar mid-sentence.
          if (avatarSpeaking.current || voice.current.audioOnlySpeaking) voice.current.interrupt();
          setTurn('hearing');
        },
        onSpeechStopped: () => {
          current.current ??= { turn: metrics.current.length + 1 };
          current.current.speechStoppedAt = performance.now();
        },
        onPartial: (_id, text) => setLive(text),
        onFinal: (_id, text) => {
          if (!text || busy.current || paused.current) return;
          current.current ??= { turn: metrics.current.length + 1 };
          current.current.finalAt = performance.now();
          pendingText.current.push(text);
          caption('you', text);
          setLive('');
          // Natural pauses: wait briefly in case the employee continues.
          if (submitTimer.current) window.clearTimeout(submitTimer.current);
          submitTimer.current = window.setTimeout(() => { submitTimer.current = null; void submit(); }, SUBMIT_GRACE_MS);
        },
        onState: (s, detail) => {
          if (s === 'listening') setMicStatus(muted.current ? 'muted' : 'listening');
          if (s === 'failed') { setMicStatus('failed'); setNotice(detail || 'Speech recognition disconnected.'); }
        },
      };
      const recognizer = new RealtimeStt(handlers);
      stt.current = recognizer;
      // The avatar greets and asks even if the microphone fails, so the employee
      // sees what happened; the fallback panel then offers turn-based voice or typing.
      let micProblem = '';
      try {
        if (!session.transcription) throw new Error('unavailable');
        await recognizer.start(session.transcription.client_secret, session.transcription.webrtc_url);
      } catch (err) {
        const denied = err instanceof DOMException && (err.name === 'NotAllowedError' || err.name === 'SecurityError' || err.name === 'NotFoundError');
        setMicStatus(denied ? 'denied' : 'failed');
        stt.current = null;
        micProblem = denied ? 'Microphone access is blocked or no microphone was found. Allow the microphone and try again, or continue below.'
          : 'Live speech recognition could not connect. You can try again, or continue below.';
      }
      listen(false);
      setPhase('live');
      if (micProblem) setFallback(micProblem);
      // Greet, then ask whatever the interview is waiting on (only messages after
      // the employee's last answer are new to them).
      const lastInbound = Math.max(0, ...messages.filter((m) => m.direction === 'inbound').map((m) => m.id));
      lastSeenId.current = lastInbound;
      await say({ phrase: 'greeting' }, 'Hi, thanks for joining. I\'ll ask you a few questions about your work. Just answer out loud, in your own words, and take your time.');
      await speakNew(messages);
      listen(true);
    } catch (err) {
      setPhase('error');
      setError(err instanceof Error ? err.message : 'Could not start the live interview.');
    }
  }, [caption, listen, navigate, say, speakNew, submit, token]);

  const togglePause = () => {
    if (phase === 'paused') {
      paused.current = false;
      setPhase('live');
      void (async () => {
        await say({ phrase: 'resumed' }, 'Welcome back. Let\'s carry on.');
        if (lastQuestionId.current) await say({ messageId: lastQuestionId.current });
        listen(true);
      })();
    } else {
      paused.current = true;
      voice.current.interrupt();
      listen(false);
      setTurn('idle');
      setPhase('paused');
    }
  };

  const toggleMute = () => {
    muted.current = !muted.current;
    stt.current?.setListening(!muted.current && !paused.current && !busy.current);
    setMicStatus(muted.current ? 'muted' : 'listening');
  };

  const end = useCallback(async () => {
    await teardown();
    setPhase((p) => (p === 'completed' ? p : 'ended'));
    setMicStatus('off');
    setAvatarStatus('off');
  }, [teardown]);

  // Leaving the page or closing the tab ends the live avatar session.
  useEffect(() => {
    const leave = () => { stt.current?.close(); void voice.current.close(); };
    window.addEventListener('pagehide', leave);
    return () => { window.removeEventListener('pagehide', leave); leave(); };
  }, []);

  const turnLabel = { idle: '', listening: 'Listening — answer whenever you are ready', hearing: 'Hearing you…',
    thinking: 'Noting your answer…', speaking: 'Speaking' }[turn];

  return (
    <div className="flex min-h-screen flex-col bg-background text-foreground">
      <header className="flex flex-wrap items-center justify-between gap-2 border-b border-border px-4 py-3">
        <div className="font-semibold">AI avatar interview</div>
        <div className="flex flex-wrap items-center gap-3 text-sm text-muted-foreground" aria-live="polite">
          <span className="flex items-center gap-1" data-testid="avatar-status">
            {avatarStatus === 'connected' ? <Wifi className="h-4 w-4" /> : <WifiOff className="h-4 w-4" />}
            {{ connecting: 'Avatar connecting', connected: 'Avatar connected', 'audio-only': 'Voice only', off: 'Avatar off' }[avatarStatus]}
          </span>
          <span className="flex items-center gap-1" data-testid="mic-status">
            {micStatus === 'listening' ? <Mic className="h-4 w-4" /> : <MicOff className="h-4 w-4" />}
            {{ off: 'Microphone off', connecting: 'Microphone connecting', listening: 'Microphone on', muted: 'Muted',
              denied: 'Microphone blocked', failed: 'Speech recognition unavailable' }[micStatus]}
          </span>
        </div>
      </header>

      <main className="mx-auto flex w-full max-w-4xl flex-1 flex-col gap-4 px-4 py-4">
        <div className="relative mx-auto aspect-square w-full max-w-md overflow-hidden rounded-xl bg-muted">
          <video ref={videoRef} autoPlay playsInline className="h-full w-full object-cover" data-testid="avatar-video" />
          <audio ref={audioRef} autoPlay />
          {avatarStatus !== 'connected' && (
            <div className="absolute inset-0 flex items-center justify-center text-sm text-muted-foreground">
              {phase === 'start' ? 'The avatar appears when you start.' : avatarStatus === 'audio-only' ? 'Voice-only mode' : 'Connecting…'}
            </div>
          )}
          {turnLabel && phase === 'live' && (
            <div className="absolute bottom-2 left-2 right-2 rounded-md bg-background/85 px-3 py-1.5 text-center text-sm" data-testid="turn-status">{turnLabel}</div>
          )}
        </div>

        {phase === 'start' && (
          <div className="mx-auto flex max-w-md flex-col items-center gap-3 text-center">
            <p className="text-sm text-muted-foreground">
              You will talk with an AI interviewer. It listens automatically — just answer out loud. You can pause, mute or switch to typing at any time, and your answers are saved as you go.
            </p>
            <Button onClick={() => void start()} data-testid="avatar-start">Start the conversation</Button>
            <Link className="text-sm underline" to={`/discover/${token}/chat`}>Use the text interview instead</Link>
          </div>
        )}

        {notice && <p className="rounded-md bg-muted px-3 py-2 text-sm" role="status">{notice}</p>}

        {fallback && phase === 'live' && (
          <div className="flex flex-col items-center gap-3 rounded-md border border-border p-3 text-center" role="alert" data-testid="mic-fallback">
            <p className="text-sm">{fallback}</p>
            <div className="flex flex-wrap justify-center gap-2">
              <Button onClick={() => { setFallback(''); void end().then(() => start()); }}><RefreshCw className="mr-1 h-4 w-4" />Try the microphone again</Button>
              <Button variant="secondary" onClick={() => navigate(`/discover/${token}/chat?voice=1`)}>Use turn-based voice</Button>
              <Button variant="secondary" onClick={() => navigate(`/discover/${token}/chat`)}>Switch to typing</Button>
            </div>
          </div>
        )}

        {phase === 'error' && (
          <div className="flex flex-col items-center gap-3 text-center" role="alert">
            <p>{error}</p>
            <div className="flex flex-wrap justify-center gap-2">
              <Button onClick={() => void start()}><RefreshCw className="mr-1 h-4 w-4" />Try again</Button>
              {/* Turn-based fallback: the existing voice mode (record, then send). */}
              <Button variant="secondary" onClick={() => navigate(`/discover/${token}/chat?voice=1`)}>Use turn-based voice</Button>
              <Button variant="secondary" onClick={() => navigate(`/discover/${token}/chat`)}>Switch to typing</Button>
            </div>
          </div>
        )}

        {(phase === 'live' || phase === 'paused') && (
          <div className="flex flex-wrap justify-center gap-2">
            <Button variant="secondary" onClick={togglePause} data-testid="avatar-pause">
              {phase === 'paused' ? <><Play className="mr-1 h-4 w-4" />Resume</> : <><Pause className="mr-1 h-4 w-4" />Pause</>}
            </Button>
            <Button variant="secondary" onClick={toggleMute} data-testid="avatar-mute">
              {micStatus === 'muted' ? <><Mic className="mr-1 h-4 w-4" />Unmute</> : <><MicOff className="mr-1 h-4 w-4" />Mute</>}
            </Button>
            <Button variant="secondary" onClick={() => setShowCaptions((v) => !v)}><Captions className="mr-1 h-4 w-4" />{showCaptions ? 'Hide' : 'Show'} captions</Button>
            <Button variant="secondary" onClick={() => void end()} data-testid="avatar-end"><PhoneOff className="mr-1 h-4 w-4" />End session</Button>
          </div>
        )}

        {(phase === 'ended' || phase === 'completed') && (
          <div className="flex flex-col items-center gap-2 text-center">
            <p>{phase === 'completed' ? 'The interview is complete. Thank you.' : 'Session ended. Your answers so far are saved.'}</p>
            <Button variant="secondary" onClick={() => navigate(`/discover/${token}/chat`)}>Open the text interview</Button>
          </div>
        )}

        {showCaptions && (captions.length > 0 || live) && (
          <section className="flex max-h-72 flex-col gap-2 overflow-y-auto rounded-lg border border-border p-3 text-sm" aria-label="Live captions" data-testid="captions">
            {captions.map((c) => (
              <p key={c.id} className={c.who === 'you' ? 'text-right' : ''}>
                <span className="mr-1 text-xs uppercase tracking-wide text-muted-foreground">{c.who === 'you' ? 'You' : 'Interviewer'}</span>
                <span className="whitespace-pre-line">{c.text}</span>
              </p>
            ))}
            {live && <p className="text-right italic text-muted-foreground">{live}</p>}
          </section>
        )}

        {debug && metrics.current.length > 0 && (
          <pre className="overflow-x-auto rounded-md bg-muted p-2 text-xs" data-testid="avatar-metrics">
            {metrics.current.map((m) => `turn ${m.turn}: speech-end→final ${ms(m.finalAt, m.speechStoppedAt)} · final→submit ${ms(m.submittedAt, m.finalAt)} · submit→ack audio ${ms(m.ackFirstAudioAt, m.submittedAt)} · submit→engine reply ${ms(m.replyAt, m.submittedAt)} · speech-end→next question audio ${ms(m.questionFirstAudioAt, m.speechStoppedAt)}`).join('\n')}
          </pre>
        )}
      </main>
    </div>
  );
}

function ms(a?: number | null, b?: number | null) {
  return a && b ? `${Math.round(a - b)} ms` : '–';
}
