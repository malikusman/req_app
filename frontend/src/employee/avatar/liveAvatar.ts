/**
 * LiveAvatar (June HR) for the live interview, via the official Web SDK.
 *
 * One architecture: LiveAvatar FULL in restricted mode. The server mints the
 * session WITHOUT a context or LLM, so LiveAvatar "will not respond to user
 * input": it listens (microphone, voice activity detection, transcription) and
 * speaks the text we send with `repeat()` (`avatar.speak_text`) in June's own
 * voice. The Employee Discovery V2 engine writes every word.
 *
 * This module adds what a natural conversation needs on top of the SDK:
 *  - an utterance queue (a backchannel is never cut off by the next question) that
 *    never hangs on a lost event;
 *  - echo protection (June's own words picked up by the microphone are never sent
 *    as the employee's answer);
 *  - a guard that silences any speech we did not send.
 *
 * The SDK is imported lazily and behind a small interface, so tests drive a fake
 * session and LiveKit never loads outside the avatar page.
 */

/** The part of `LiveAvatarSession` this module uses. */
export interface LiveAvatarSessionLike {
  start(): Promise<void>;
  stop(): Promise<void>;
  attach(element: HTMLMediaElement): void;
  repeat(text: string): string;
  interrupt(): void;
  on(event: string, listener: (...args: any[]) => void): unknown; // eslint-disable-line @typescript-eslint/no-explicit-any
  voiceChat: { mute(): unknown; unmute(): unknown };
}

export type LiveAvatarFactory = (sessionToken: string) => Promise<LiveAvatarSessionLike>;

declare global { interface Window { __liveAvatarFactory?: LiveAvatarFactory } }

export const sdkFactory: LiveAvatarFactory = async (sessionToken) => {
  const { LiveAvatarSession } = await import('@heygen/liveavatar-web-sdk');
  // The microphone is published to LiveAvatar (it is June's ears); the SDK opens
  // it with echo cancellation and noise suppression.
  return new LiveAvatarSession(sessionToken, { autoKeepAlive: true, voiceChat: {} }) as unknown as LiveAvatarSessionLike;
};

/** Mocked end-to-end tests (dev builds only) may substitute a fake session. */
export function resolveFactory(): LiveAvatarFactory {
  if (import.meta.env?.DEV && typeof window !== 'undefined' && window.__liveAvatarFactory) return window.__liveAvatarFactory;
  return sdkFactory;
}

// SDK event names (SessionEvent / AgentEventsEnum string values, SDK 0.0.20).
export const LA_EVENTS = {
  streamReady: 'session.stream_ready',
  disconnected: 'session.disconnected',
  stopped: 'session.stopped',
  userSpeakStarted: 'user.speak_started',
  userSpeakEnded: 'user.speak_ended',
  userTranscription: 'user.transcription',
  userTranscriptionChunk: 'user.transcription.chunk',
  avatarSpeakStarted: 'avatar.speak_started',
  avatarSpeakEnded: 'avatar.speak_ended',
  avatarTranscription: 'avatar.transcription',
} as const;

export type LiveAvatarHandlers = {
  onSpeaking: (speaking: boolean) => void;
  onDisconnected: (reason: string) => void;
  onUserSpeechStarted: () => void;
  onUserSpeechStopped: () => void;
  onUserPartial: (text: string) => void;
  onUserFinal: (text: string) => void;
  /** The avatar said words the engine did not send; it has already been silenced. */
  onUnexpectedSpeech?: (detail: string) => void;
  /** Debug only: a transcript was dropped (June's own voice, filler or a silence artefact). */
  onEchoDropped?: (text: string) => void;
};

export type SpeakResult = { firstAudioAt: number | null; interrupted: boolean; started: boolean };

const START_TIMEOUT_MS = 45_000;
// A line that never starts (a lost event) must not stall the interview.
const SPEAK_START_TIMEOUT_MS = 8_000;
// Once started: a generous estimate of the time to say it, then move on anyway.
const SPEAK_BASE_MS = 4_000;
const SPEAK_MS_PER_WORD = 450;
// After June stops, a transcript of her own words can still arrive briefly.
const ECHO_WINDOW_MS = 2_500;

/** The text the avatar speaks for an interviewer message (mirrors the server's speech normalisation). */
export function spokenText(text: string): string {
  return text
    .replace(/^\s*[•\-*]\s*/gm, '')
    .replace(/(\d)\s*[–—-]\s*(\d)/g, '$1 to $2')
    .replace(/\s*\n+\s*/g, '. ')
    .replace(/ {2,}/g, ' ')
    .replace(/\.\s*\./g, '.')
    .replace(/:\s*\./g, ':')
    .trim();
}

function words(text: string): string[] {
  return text.toLowerCase().replace(/[^\p{L}\p{N}\s]/gu, ' ').split(/\s+/).filter(Boolean);
}

/** Share of the heard words that appear in one of the sent texts (best match). */
export function overlapWithSent(transcript: string, sent: string[]): number {
  const heard = words(transcript);
  if (!heard.length) return 1;
  return Math.max(0, ...sent.map((text) => {
    const said = new Set(words(text));
    return heard.filter((w) => said.has(w)).length / heard.length;
  }));
}

/** True when an avatar transcript is (part of) something we asked it to say. */
export function matchesSent(transcript: string, sent: string[]): boolean {
  return overlapWithSent(transcript, sent) >= 0.6;
}

/**
 * True when a "user" transcript is really June's own voice picked up by the
 * microphone: at least three words, nearly all of them from what she just said.
 * A short real answer ("yes", "that's right") is never treated as echo.
 */
export function isEcho(transcript: string, sent: string[], whileSpeaking = false): boolean {
  const n = words(transcript).length;
  if (n >= 3 && overlapWithSent(transcript, sent) >= 0.85) return true;
  // While June is still talking, a 2+ word transcript made only of her words is her.
  return whileSpeaking && n >= 2 && overlapWithSent(transcript, sent) === 1;
}

const FILLER = new Set(['um', 'umm', 'uh', 'uhh', 'erm', 'er', 'ah', 'eh', 'hmm', 'hm', 'mm', 'mmm', 'mhm', 'oh']);
// Phrases speech recognisers produce from silence or background noise.
const SILENCE_ARTEFACTS = /^(?:thanks? for watching|thank you for watching|subtitles? by.*|you|bye|\.+)$/i;

/** True when a transcript carries no answer: empty, only fillers, or a silence artefact. */
export function isNoise(transcript: string): boolean {
  const heard = words(transcript);
  if (!heard.length) return true;
  if (heard.every((w) => FILLER.has(w))) return true;
  return SILENCE_ARTEFACTS.test(transcript.trim().replace(/[.!?,\s]+$/, ''));
}

/**
 * Adds one transcript segment to the answer being assembled. LiveAvatar may resend
 * a segment, or send a cumulative transcript that repeats earlier segments; both
 * are folded in so nothing is duplicated and nothing is lost.
 */
export function mergeSegment(parts: string[], text: string): string[] {
  const norm = (s: string) => words(s).join(' ');
  const added = norm(text);
  if (!added) return parts;
  const joined = norm(parts.join(' '));
  if (joined === added || joined.endsWith(` ${added}`) || (parts.length && norm(parts[parts.length - 1]) === added)) return parts;
  if (joined && added.startsWith(`${joined} `)) return [text]; // cumulative: replaces what we had
  return [...parts, text];
}

// End of turn, after LiveAvatar's own voice detection has sent the transcript.
export const END_OF_TURN_MS = 1400;
// The words so far end mid-thought ("...and", "...so the", "...because,"): wait longer.
export const INCOMPLETE_END_OF_TURN_MS = 3000;
// A 1-2 word fragment ("So the...") usually means a mid-sentence pause.
export const FRAGMENT_END_OF_TURN_MS = 2600;
const COMPLETE_SHORT_ANSWER = /^(yes|yeah|yep|yup|no|nope|correct|right|exactly|sure|ok(?:ay)?|that'?s (?:right|correct|all|it)|continue|i agree|not really|none|nothing|daily|weekly|monthly|never|sometimes|always)\b/i;
const INCOMPLETE_ENDING = /(?:[,;:–—-]|\.\.\.|…|\b(?:and|but|or|so|because|then|also|like|just|with|to|for|of|the|a|an|my|our|their|which|that|when|where|if|um|uh|er|is|are|was|were|i|we))\s*$/i;

/** How long to wait for more speech before the assembled answer is sent. */
export function endOfTurnMs(heard: string): number {
  const text = heard.trim();
  const count = words(text).length;
  if (count <= 2 && !COMPLETE_SHORT_ANSWER.test(text)) return FRAGMENT_END_OF_TURN_MS;
  if (INCOMPLETE_ENDING.test(text)) return INCOMPLETE_END_OF_TURN_MS;
  return END_OF_TURN_MS;
}

type Pending = { text: string; resolve: (r: SpeakResult) => void; firstAudioAt: number | null; started: boolean;
  timer: ReturnType<typeof setTimeout> | undefined };

export class LiveAvatarRenderer {
  private session: LiveAvatarSessionLike | null = null;
  private readonly handlers: LiveAvatarHandlers;
  private pending: Pending | null = null;
  private queue: Promise<unknown> = Promise.resolve();
  private generation = 0;
  private recentlySent: { text: string; at: number }[] = [];
  private lastSpeechEndedAt = -Infinity;
  private speaking = false;
  private partial = '';
  private closed = false;

  constructor(handlers: LiveAvatarHandlers) {
    this.handlers = handlers;
  }

  async connect(sessionToken: string, video: HTMLVideoElement, factory: LiveAvatarFactory = resolveFactory()) {
    const session = await factory(sessionToken);
    this.session = session;
    session.on(LA_EVENTS.streamReady, () => session.attach(video));
    session.on(LA_EVENTS.disconnected, (reason: unknown) => this.disconnected(String(reason ?? 'disconnected')));
    session.on(LA_EVENTS.stopped, (event: { stop_reason?: string; end_reason?: string }) =>
      this.disconnected(event?.stop_reason || event?.end_reason || 'session stopped'));
    session.on(LA_EVENTS.avatarSpeakStarted, () => this.avatarStarted());
    session.on(LA_EVENTS.avatarSpeakEnded, () => this.avatarEnded());
    session.on(LA_EVENTS.avatarTranscription, (event: { text?: string }) => this.avatarSaid(event?.text ?? ''));
    session.on(LA_EVENTS.userSpeakStarted, () => { this.partial = ''; this.handlers.onUserSpeechStarted(); });
    session.on(LA_EVENTS.userSpeakEnded, () => this.handlers.onUserSpeechStopped());
    session.on(LA_EVENTS.userTranscriptionChunk, (event: { text?: string }) => {
      const chunk = event?.text ?? '';
      // Chunks may be cumulative or deltas; accept both.
      this.partial = chunk.startsWith(this.partial) ? chunk : `${this.partial} ${chunk}`.trim();
      if (!this.looksLikeEcho(this.partial)) this.handlers.onUserPartial(this.partial);
    });
    session.on(LA_EVENTS.userTranscription, (event: { text?: string }) => {
      this.partial = '';
      const text = (event?.text ?? '').trim();
      if (isNoise(text)) { if (text) this.handlers.onEchoDropped?.(text); return; }
      if (this.looksLikeEcho(text)) { this.handlers.onEchoDropped?.(text); return; }
      this.handlers.onUserFinal(text);
    });
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      await Promise.race([
        session.start(),
        new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('LiveAvatar did not start in time')), START_TIMEOUT_MS); }),
      ]);
    } catch (err) {
      void session.stop().catch(() => undefined);
      this.session = null;
      throw err;
    } finally {
      clearTimeout(timer);
    }
    session.attach(video);
  }

  get connected() {
    return Boolean(this.session) && !this.closed;
  }

  get isSpeaking() {
    return this.speaking;
  }

  /**
   * Queue one line for June to say, exactly as given. Resolves when she has
   * finished it, was interrupted, or the line was dropped by `interrupt()`.
   */
  say(text: string): Promise<SpeakResult> {
    const generation = this.generation;
    const run = this.queue.then(() => (generation === this.generation && this.session
      ? this.speakNow(text) : { firstAudioAt: null, interrupted: true, started: false }));
    this.queue = run.catch(() => undefined);
    return run;
  }

  /** Whether LiveAvatar may hear the employee (paused / muted turn it off). */
  setUserListening(on: boolean) {
    if (!this.session) return;
    try { if (on) this.session.voiceChat.unmute(); else this.session.voiceChat.mute(); } catch { /* not started yet */ }
  }

  /** Barge-in: stop June mid-sentence and drop anything queued. */
  interrupt() {
    this.generation += 1;
    try { this.session?.interrupt(); } catch { /* not connected */ }
    this.finishPending(true);
    this.setSpeaking(false);
  }

  async close() {
    this.closed = true;
    this.generation += 1;
    this.finishPending(true);
    const session = this.session;
    this.session = null;
    try { await session?.stop(); } catch { /* already closed */ }
  }

  private speakNow(text: string): Promise<SpeakResult> {
    const session = this.session;
    if (!session || !text.trim()) return Promise.resolve({ firstAudioAt: null, interrupted: false, started: false });
    return new Promise((resolve) => {
      const pending: Pending = { text, resolve, firstAudioAt: null, started: false, timer: undefined };
      pending.timer = setTimeout(() => { if (this.pending === pending) this.finishPending(false); }, SPEAK_START_TIMEOUT_MS);
      this.pending = pending;
      const now = performance.now();
      this.recentlySent = [...this.recentlySent.filter((s) => now - s.at < 120_000), { text, at: now }];
      try {
        session.repeat(text);
      } catch {
        this.finishPending(false);
      }
    });
  }

  private looksLikeEcho(text: string) {
    const recent = this.speaking || performance.now() - this.lastSpeechEndedAt < ECHO_WINDOW_MS;
    return recent && isEcho(text, this.recentlySent.slice(-3).map((s) => s.text), this.speaking);
  }

  private avatarStarted() {
    const pending = this.pending;
    if (pending && !pending.started) {
      pending.started = true;
      pending.firstAudioAt = performance.now();
      // Re-arm: from now on, allow time to say the whole line.
      clearTimeout(pending.timer);
      const estimate = SPEAK_BASE_MS + pending.text.split(/\s+/).length * SPEAK_MS_PER_WORD;
      pending.timer = setTimeout(() => { if (this.pending === pending) this.finishPending(false); }, estimate);
    }
    this.setSpeaking(true);
  }

  private avatarEnded() {
    this.lastSpeechEndedAt = performance.now();
    if (this.pending?.started) this.finishPending(false);
    this.setSpeaking(false);
  }

  private avatarSaid(text: string) {
    if (!text.trim()) return;
    if (matchesSent(text, this.recentlySent.map((s) => s.text))) return;
    // Restricted mode should make this impossible; if LiveAvatar ever improvises,
    // June is silenced at once and the interview carries on with the engine.
    try { this.session?.interrupt(); } catch { /* ignore */ }
    this.finishPending(true);
    this.setSpeaking(false);
    this.handlers.onUnexpectedSpeech?.('The avatar said something the interview did not ask');
  }

  private finishPending(interrupted: boolean) {
    const pending = this.pending;
    if (!pending) return;
    this.pending = null;
    clearTimeout(pending.timer);
    pending.resolve({ firstAudioAt: pending.firstAudioAt, interrupted, started: pending.started });
  }

  private setSpeaking(speaking: boolean) {
    if (this.speaking === speaking) return;
    this.speaking = speaking;
    this.handlers.onSpeaking(speaking);
  }

  private disconnected(reason: string) {
    if (this.closed) return;
    this.closed = true;
    this.generation += 1;
    this.finishPending(true);
    this.setSpeaking(false);
    this.session = null;
    this.handlers.onDisconnected(reason);
  }
}
