import { expect, test } from '@playwright/test';
import {
  LA_EVENTS,
  LiveAvatarRenderer,
  END_OF_TURN_MS,
  FRAGMENT_END_OF_TURN_MS,
  INCOMPLETE_END_OF_TURN_MS,
  endOfTurnMs,
  isEcho,
  isNoise,
  mergeSegment,
  matchesSent,
  spokenText,
  type LiveAvatarHandlers,
  type LiveAvatarSessionLike,
} from '../src/employee/avatar/liveAvatar';

// LiveAvatar FULL renderer logic against a FAKE session (no browser, no network,
// no LiveAvatar API calls, no credits). The real SDK is never imported here.

class FakeSession implements LiveAvatarSessionLike {
  listeners = new Map<string, ((...a: any[]) => void)[]>(); // eslint-disable-line @typescript-eslint/no-explicit-any
  repeated: string[] = [];
  interrupts = 0;
  muted: boolean[] = [];
  started = false;
  stopped = false;
  voiceChat = { mute: () => this.muted.push(true), unmute: () => this.muted.push(false) };
  async start() { this.started = true; }
  async stop() { this.stopped = true; }
  attach() { /* no media in node */ }
  repeat(text: string) { this.repeated.push(text); return 'evt'; }
  interrupt() { this.interrupts += 1; }
  on(event: string, listener: (...a: any[]) => void) { // eslint-disable-line @typescript-eslint/no-explicit-any
    this.listeners.set(event, [...(this.listeners.get(event) ?? []), listener]);
  }
  emit(event: string, payload: object = {}) { (this.listeners.get(event) ?? []).forEach((l) => l(payload)); }
}

function setup() {
  const session = new FakeSession();
  const log: string[] = [];
  const handlers: LiveAvatarHandlers = {
    onSpeaking: (s) => log.push(`speaking:${s}`),
    onDisconnected: (r) => log.push(`disconnected:${r}`),
    onUserSpeechStarted: () => log.push('user:start'),
    onUserSpeechStopped: () => log.push('user:stop'),
    onUserPartial: (t) => log.push(`partial:${t}`),
    onUserFinal: (t) => log.push(`final:${t}`),
    onUnexpectedSpeech: (d) => log.push(`unexpected:${d}`),
    onEchoDropped: (t) => log.push(`echo:${t}`),
  };
  const renderer = new LiveAvatarRenderer(handlers);
  return { session, log, renderer, connect: () => renderer.connect('token', {} as HTMLVideoElement, async () => session) };
}

const tick = () => new Promise((r) => setTimeout(r, 0));

test('interviewer text is spoken as the server normalises it', () => {
  expect(spokenText('• Weekly report: every Monday; 1–2 hours\n• Payroll')).toBe('Weekly report: every Monday; 1 to 2 hours. Payroll');
});

test('avatar transcripts are matched against what we asked it to say', () => {
  const sent = ['What is your job title?', 'Thank you.'];
  expect(matchesSent('what is your job title', sent)).toBe(true);
  expect(matchesSent('Thank you!', sent)).toBe(true);
  expect(matchesSent('I think you should ask your manager about the payroll system', sent)).toBe(false);
});

test('echo detection: June\'s own words are echo, a real short answer never is', () => {
  const sent = ['How often do you prepare the weekly payroll report?'];
  expect(isEcho('how often do you prepare the weekly payroll', sent)).toBe(true);
  expect(isEcho('weekly', sent)).toBe(false); // short answers are always the employee's
  expect(isEcho('Every Monday, about two hours.', sent)).toBe(false);
});

test('echo while June is still speaking: two or more of her own words are dropped', () => {
  const sent = ['Is that list complete?'];
  expect(isEcho('list complete', sent, true)).toBe(true);
  expect(isEcho('list complete', sent, false)).toBe(false);
  expect(isEcho('yes', sent, true)).toBe(false);
});

test('silence artefacts and fillers are not answers', () => {
  for (const t of ['', '.', 'Um.', 'uh hmm', 'Thanks for watching!', 'you']) expect(isNoise(t)).toBe(true);
  for (const t of ['Yes.', 'No', 'Thank you, that is all.', 'Payroll mostly.']) expect(isNoise(t)).toBe(false);
});

test('transcript segments merge into one answer without duplicates or loss', () => {
  let parts: string[] = [];
  parts = mergeSegment(parts, 'I start by checking the emails,');
  parts = mergeSegment(parts, 'I start by checking the emails,'); // resent
  parts = mergeSegment(parts, 'and then the invoices.');
  expect(parts.join(' ')).toBe('I start by checking the emails, and then the invoices.');
  // A cumulative transcript replaces the pieces it already contains.
  expect(mergeSegment(['I start'], 'I start with payroll checks.')).toEqual(['I start with payroll checks.']);
  expect(mergeSegment(['a b c'], 'b c')).toEqual(['a b c']);
  expect(mergeSegment(['first'], '  ')).toEqual(['first']);
});

test('end of turn waits longer for a fragment or a sentence left open', () => {
  expect(endOfTurnMs('I review the supplier invoices.')).toBe(END_OF_TURN_MS);
  expect(endOfTurnMs('Yes')).toBe(END_OF_TURN_MS);
  expect(endOfTurnMs('So the')).toBe(FRAGMENT_END_OF_TURN_MS);
  expect(endOfTurnMs('I check the emails, coordinate with hiring managers, and just')).toBe(INCOMPLETE_END_OF_TURN_MS);
  expect(endOfTurnMs('Mostly invoices and')).toBe(INCOMPLETE_END_OF_TURN_MS);
  expect(endOfTurnMs('First the emails,')).toBe(INCOMPLETE_END_OF_TURN_MS);
});

test('speaks the exact text, resolves on speak_ended, and forwards the employee\'s speech', async () => {
  const { session, log, renderer, connect } = setup();
  await connect();
  expect(session.started).toBe(true);

  const done = renderer.say('What is your job title?');
  await tick();
  expect(session.repeated).toEqual(['What is your job title?']);
  session.emit(LA_EVENTS.avatarSpeakStarted);
  session.emit(LA_EVENTS.avatarTranscription, { text: 'What is your job title?' });
  session.emit(LA_EVENTS.avatarSpeakEnded);
  const result = await done;
  expect(result).toMatchObject({ interrupted: false, started: true });
  expect(result.firstAudioAt).not.toBeNull();

  session.emit(LA_EVENTS.userSpeakStarted);
  session.emit(LA_EVENTS.userTranscriptionChunk, { text: "I'm an" });
  session.emit(LA_EVENTS.userTranscriptionChunk, { text: "I'm an HR officer" });
  session.emit(LA_EVENTS.userSpeakEnded);
  session.emit(LA_EVENTS.userTranscription, { text: " I'm an HR officer. " });
  expect(log).toEqual(['speaking:true', 'speaking:false', 'user:start', "partial:I'm an", "partial:I'm an HR officer",
    'user:stop', "final:I'm an HR officer."]);

  renderer.setUserListening(false);
  renderer.setUserListening(true);
  expect(session.muted).toEqual([true, false]);
});

test('lines are queued in order: a backchannel is never cut off by the next question', async () => {
  const { session, renderer, connect } = setup();
  await connect();
  const ack = renderer.say('Mm-hm.');
  const question = renderer.say('And after that?');
  await tick();
  expect(session.repeated).toEqual(['Mm-hm.']); // the question waits
  session.emit(LA_EVENTS.avatarSpeakStarted);
  session.emit(LA_EVENTS.avatarSpeakEnded);
  await ack;
  await tick();
  expect(session.repeated).toEqual(['Mm-hm.', 'And after that?']);
  session.emit(LA_EVENTS.avatarSpeakStarted);
  session.emit(LA_EVENTS.avatarSpeakEnded);
  expect((await question).interrupted).toBe(false);
});

test('barge-in stops June and drops queued lines', async () => {
  const { session, renderer, connect } = setup();
  await connect();
  const first = renderer.say('Here is what I captured so far.');
  const second = renderer.say('Is that right?');
  await tick();
  session.emit(LA_EVENTS.avatarSpeakStarted);
  renderer.interrupt();
  expect(session.interrupts).toBe(1);
  expect((await first).interrupted).toBe(true);
  expect((await second).interrupted).toBe(true);
  expect(session.repeated).toEqual(['Here is what I captured so far.']);
});

test('June\'s own voice picked up by the microphone is never sent as an answer', async () => {
  const { session, log, renderer, connect } = setup();
  await connect();
  const done = renderer.say('What does a typical Monday look like for you?');
  await tick();
  session.emit(LA_EVENTS.avatarSpeakStarted);
  session.emit(LA_EVENTS.userTranscription, { text: 'what does a typical Monday look like' });
  session.emit(LA_EVENTS.avatarSpeakEnded);
  await done;
  session.emit(LA_EVENTS.userTranscription, { text: 'I start with the payroll checks.' });
  expect(log.filter((l) => l.startsWith('final:') || l.startsWith('echo:'))).toEqual([
    'echo:what does a typical Monday look like', 'final:I start with the payroll checks.']);
});

test('a line whose events are lost does not hang the interview', async () => {
  const { renderer, connect } = setup();
  await connect();
  const original = globalThis.setTimeout;
  // Run timers instantly so the start timeout fires.
  globalThis.setTimeout = ((fn: () => void) => original(fn, 0)) as typeof setTimeout;
  try {
    const result = await renderer.say('Hello?');
    expect(result).toMatchObject({ interrupted: false, started: false });
  } finally {
    globalThis.setTimeout = original;
  }
});

test('guard: speech the engine did not send is stopped and reported', async () => {
  const { session, log, renderer, connect } = setup();
  await connect();
  const done = renderer.say('Thank you.');
  await tick();
  session.emit(LA_EVENTS.avatarSpeakStarted);
  session.emit(LA_EVENTS.avatarSpeakEnded);
  await done;
  // An improvised LLM answer: different words.
  session.emit(LA_EVENTS.avatarTranscription, { text: 'Sure! As an HR assistant I can help you with leave policies today.' });
  expect(log.filter((l) => l.startsWith('unexpected'))).toHaveLength(1);
  expect(session.interrupts).toBe(1);
});

test('a LiveAvatar-side stop is reported once, and close() stops the session', async () => {
  const first = setup();
  await first.connect();
  first.session.emit(LA_EVENTS.stopped, { stop_reason: 'MAX_DURATION_REACHED' });
  first.session.emit(LA_EVENTS.disconnected, 'SERVER_INITIATED');
  expect(first.log.filter((l) => l.startsWith('disconnected'))).toEqual(['disconnected:MAX_DURATION_REACHED']);

  const second = setup();
  await second.connect();
  await second.renderer.close();
  expect(second.session.stopped).toBe(true);
  expect(second.renderer.connected).toBe(false);
  expect(second.log.filter((l) => l.startsWith('disconnected'))).toEqual([]); // our own close is not a failure
});

test('a session that fails to start is stopped and the error surfaces', async () => {
  const session = new FakeSession();
  session.start = async () => { throw new Error('no credits'); };
  const renderer = new LiveAvatarRenderer({
    onSpeaking: () => {}, onDisconnected: () => {}, onUserSpeechStarted: () => {}, onUserSpeechStopped: () => {},
    onUserPartial: () => {}, onUserFinal: () => {},
  });
  await expect(renderer.connect('t', {} as HTMLVideoElement, async () => session)).rejects.toThrow('no credits');
  expect(session.stopped).toBe(true);
});
