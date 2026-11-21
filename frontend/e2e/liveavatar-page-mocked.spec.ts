import { expect, test, type Page, type Route } from '@playwright/test';

/**
 * The avatar interview page (LiveAvatar FULL only) MOCKED end to end: every Mjadi
 * API call is answered by the test, the LiveAvatar SDK is replaced by a fake
 * session (dev builds only: window.__liveAvatarFactory), and any request to
 * LiveAvatar, LiveKit or OpenAI is blocked and fails the test. No session starts
 * and no credits are used.
 *
 * Run against a Vite dev server (the fake hook is compiled out of production):
 *   E2E_BASE_URL=http://localhost:5173 npx playwright test e2e/liveavatar-page-mocked.spec.ts
 */
const LINK = 'mock-link';
const Q1 = 'What is your job title?';
const CONSENT = 'This is a conversation about the work you actually do day to day. You can pause, switch to typing, or stop at any time.';
const Q2 = '• Weekly report: every Monday; 1–2 hours\nIs that right?';
const TEXTS = {
  acknowledgements: ['Mm-hm.', 'Okay.', 'Right.', 'I see.'],
  phrases: {
    greeting: "Hi, I'm June. Thanks for making the time. Just talk naturally.",
    rephrase: 'Sorry, could you say it again?', still_working: 'Just a moment.', resumed: "Welcome back. Let's pick up where we left off.",
  },
};

type Fake = { repeated: string[][]; interrupts: number; muted: boolean[]; stops: number; modes: string[] };

async function installFakeLiveAvatar(page: Page, opts: { speakMs: number }) {
  await page.addInitScript(({ speakMs }) => {
    type L = (...a: unknown[]) => void;
    const state = { repeated: [] as string[][], interrupts: 0, muted: [] as boolean[], stops: 0, modes: [] as string[], sessions: [] as unknown[] };
    (window as unknown as { __la: typeof state }).__la = state;
    (window as unknown as { __liveAvatarFactory: unknown }).__liveAvatarFactory = async () => {
      const listeners = new Map<string, L[]>();
      const emit = (e: string, p: unknown = {}) => (listeners.get(e) ?? []).forEach((l) => l(p));
      const index = state.modes.push('FULL') - 1;
      state.repeated[index] = [];
      let speaking: number | null = null;
      const session = {
        emit,
        voiceChat: { mute: () => state.muted.push(true), unmute: () => state.muted.push(false) },
        on: (e: string, l: L) => listeners.set(e, [...(listeners.get(e) ?? []), l]),
        start: async () => { emit('session.stream_ready'); },
        stop: async () => { state.stops += 1; },
        attach: () => undefined,
        repeat: (text: string) => {
          state.repeated[index].push(text);
          setTimeout(() => {
            emit('avatar.speak_started');
            emit('avatar.transcription', { text });
            speaking = window.setTimeout(() => { speaking = null; emit('avatar.speak_ended'); }, speakMs);
          }, 20);
          return 'evt';
        },
        interrupt: () => {
          state.interrupts += 1;
          if (speaking) { clearTimeout(speaking); speaking = null; emit('avatar.speak_ended'); }
        },
      };
      state.sessions.push(session);
      return session;
    };
    localStorage.setItem('req_discover_session', JSON.stringify({ link: 'mock-link', token: 'mock-jwt' }));
    // Chromium sends keepalive requests (the "stop session" backstop) outside
    // Playwright's interception, so they would reach a real server. In tests they
    // are ordinary requests, answered by the mocks like every other call.
    const realFetch = window.fetch.bind(window);
    window.fetch = (input: RequestInfo | URL, init?: RequestInit) =>
      realFetch(input, init?.keepalive ? { ...init, keepalive: false } : init);
  }, opts);
}

type MockOptions = { liveavatarError?: string; awaitingConsent?: boolean; dropFirstAnswerResponse?: boolean; replyDelayMs?: number; failFirstRead?: boolean };

async function mockApi(page: Page, opts: MockOptions = {}) {
  const calls = { sessions: [] as Record<string, unknown>[], answers: [] as string[], answerMeta: [] as Record<string, unknown>[],
    submissions: new Set<string>(), consents: [] as string[], stops: 0, external: [] as string[] };
  let answered = false;
  let answeredAt = 0;
  const replied = () => answered && Date.now() - answeredAt >= (opts.replyDelayMs ?? 0);
  let onboarding = opts.awaitingConsent ? 'awaiting_consent' : 'verified';
  const state = (submissionId?: string | null) => ({ completed: false, discovery_pending: false, discovery_error: null, can_rephrase: false,
    onboarding_step: onboarding, interview_phase: 'anchor', submission_received: submissionId ? calls.submissions.has(submissionId) : null });
  const messages = () => [
    // WhatsApp consent copy from the onboarding track: never spoken or shown by the avatar.
    { id: 1, direction: 'outbound', track: 'onboarding', body: 'Before we begin ... via WhatsApp. Reply YES to continue or STOP.', created_at: '2026-11-20T09:59:00Z' },
    ...(onboarding === 'verified' ? [{ id: 2, direction: 'outbound', track: 'discovery', body: Q1, created_at: '2026-11-20T10:00:00Z' }] : []),
    ...(replied() ? [{ id: 3, direction: 'inbound', track: 'discovery', body: calls.answers[0], created_at: '2026-11-20T10:01:00Z' },
      { id: 4, direction: 'outbound', track: 'discovery', body: Q2, created_at: '2026-11-20T10:01:05Z' }] : []),
  ];
  // Nothing may reach LiveAvatar, LiveKit, OpenAI or Simli from this test.
  await page.context().route(/^(?:https?|wss?):\/\/[^/]*(?:liveavatar\.com|heygen\.com|openai\.com|livekit|simli\.(?:ai|com))/, (route: Route) => {
    calls.external.push(route.request().url());
    return route.abort();
  });
  let dropped = false;
  let failedRead = false;
  await page.context().route('**/api/v1/public/discover/**', async (route: Route) => {
    const req = route.request();
    const url = new URL(req.url());
    const json = (body: unknown) => route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(body) });
    if (url.pathname.endsWith('/voice/session/stop')) { calls.stops += 1; return json({ stopped: true }); }
    if (url.pathname.endsWith('/consent') && req.method() === 'POST') {
      calls.consents.push(JSON.parse(req.postData() || '{}').version);
      onboarding = 'verified';
      return json({ accepted: true });
    }
    if (url.pathname.endsWith('/consent')) return json({ required: onboarding === 'awaiting_consent', text: CONSENT, version: 'web-avatar-abc123abc123' });
    if (url.pathname.endsWith('/voice/session')) {
      calls.sessions.push(JSON.parse(req.postData() || '{}'));
      if (opts.liveavatarError && calls.sessions.length === 1) {
        return route.fulfill({ status: 503, contentType: 'application/json', body: JSON.stringify({ error: opts.liveavatarError, retryable: true }) });
      }
      return json({ language: 'en', provider: 'liveavatar', display_name: 'June', texts: TEXTS,
        liveavatar: { session_token: 'fake-token', session_id: `sess-${calls.sessions.length}`, mode: 'FULL', sandbox: false, max_session_duration: null } });
    }
    if (url.pathname.endsWith('/messages') && req.method() === 'POST') {
      const posted = JSON.parse(req.postData() || '{}');
      if (!calls.submissions.has(posted.submission_id)) {
        calls.answers.push(posted.body);
        calls.answerMeta.push({ input_mode: posted.input_mode, interrupted_question: posted.interrupted_question });
        calls.submissions.add(posted.submission_id);
      }
      if (!answered) answeredAt = Date.now();
      answered = true;
      if (opts.dropFirstAnswerResponse && !dropped) { dropped = true; return route.abort('connectionreset'); } // saved, response lost
      return json({ messages: messages(), state: { ...state(posted.submission_id), discovery_pending: true } });
    }
    if (url.pathname.endsWith('/messages')) {
      if (opts.failFirstRead && !failedRead) { failedRead = true; return route.abort('timedout'); } // a slow or dropped first read
      return json({ messages: messages(), state: { ...state(url.searchParams.get('submission_id')), discovery_pending: answered && !replied() } });
    }
    return route.fulfill({ status: 404, body: '{}' });
  });
  return calls;
}

// Leave the page while the mocks are still installed: its pagehide handler sends a
// keepalive "stop session" request, which must be answered by the mock, never by a
// real server.
test.afterEach(async ({ page }) => {
  await page.goto('about:blank').catch(() => undefined);
});

const fake = (page: Page) => page.evaluate(() => {
  const s = (window as unknown as { __la: Fake }).__la;
  return { repeated: s.repeated, interrupts: s.interrupts, muted: s.muted, stops: s.stops, modes: s.modes };
});
const emit = (page: Page, event: string, payload: object = {}, sessionIndex = -1) => page.evaluate(([e, p, i]) => {
  const sessions = (window as unknown as { __la: { sessions: { emit: (e: string, p?: unknown) => void }[] } }).__la.sessions;
  sessions.at(i as number)!.emit(e as string, p);
}, [event, payload, sessionIndex] as const);

test('LiveAvatar listens, the engine decides, June says exactly the engine\'s words', async ({ page }) => {
  await installFakeLiveAvatar(page, { speakMs: 150 });
  const calls = await mockApi(page);
  await page.goto(`/discover/${LINK}/avatar?debug=1`);
  await page.getByTestId('avatar-start').click();
  await expect(page.getByTestId('avatar-provider')).toHaveText('(LiveAvatar FULL)');

  // Greeting, then the engine's pending question, verbatim. WhatsApp onboarding copy is neither spoken nor shown.
  await expect.poll(async () => (await fake(page)).repeated[0]).toEqual([TEXTS.phrases.greeting, Q1]);
  await expect(page.getByTestId('captions')).not.toContainText('WhatsApp');
  await expect(page.getByTestId('mic-status')).toContainText('Microphone on');
  await expect(page.getByTestId('phase-progress')).toContainText('Your day');

  // The employee answers out loud once the question is finished; LiveAvatar transcribes it.
  await expect(page.getByTestId('turn-status')).toHaveText(/Listening/);
  await emit(page, 'user.speak_started');
  await expect(page.getByTestId('turn-status')).toHaveText('Listening to you…');
  await emit(page, 'user.transcription.chunk', { text: "I'm an HR" });
  await emit(page, 'user.speak_ended');
  await emit(page, 'user.transcription', { text: "I'm an HR officer." });

  // The answer goes through the durable message API (the V2 engine), not to a LiveAvatar LLM.
  await expect.poll(() => calls.answers).toEqual(["I'm an HR officer."]);
  expect(calls.answerMeta).toEqual([{ input_mode: 'voice', interrupted_question: false }]);
  // The reply came back quickly, so no filler: just the next question.
  await expect.poll(async () => (await fake(page)).repeated[0].slice(2)).toEqual(['Weekly report: every Monday; 1 to 2 hours. Is that right?']);
  await expect(page.getByTestId('captions')).toContainText("I'm an HR officer.");
  expect(calls.external).toEqual([]);

  await page.getByTestId('avatar-end').click();
  await expect.poll(async () => (await fake(page)).stops).toBe(1);
  await expect.poll(() => calls.stops).toBe(1); // server-side backstop stop
});

test('web consent replaces the WhatsApp "reply YES": no avatar session until the employee agrees', async ({ page }) => {
  await installFakeLiveAvatar(page, { speakMs: 100 });
  const calls = await mockApi(page, { awaitingConsent: true });
  await page.goto(`/discover/${LINK}/avatar`);
  await page.getByTestId('avatar-start').click();
  await expect(page.getByTestId('avatar-consent')).toContainText(CONSENT);
  await expect(page.getByTestId('avatar-consent')).not.toContainText(/whatsapp|reply yes/i);
  expect(calls.sessions).toEqual([]); // nothing minted, no credits
  expect((await fake(page)).modes).toEqual([]);

  await page.getByTestId('avatar-consent-accept').click();
  await expect.poll(() => calls.consents).toEqual(['web-avatar-abc123abc123']);
  await expect.poll(async () => (await fake(page)).repeated[0]).toEqual([TEXTS.phrases.greeting, Q1]);
  expect(calls.answers).toEqual([]); // consent is never sent as an interview answer
});

test('a pause mid-sentence does not cut the answer: fragments become one answer', async ({ page }) => {
  await installFakeLiveAvatar(page, { speakMs: 100 });
  const calls = await mockApi(page);
  await page.goto(`/discover/${LINK}/avatar`);
  await page.getByTestId('avatar-start').click();
  await expect(page.getByTestId('turn-status')).toHaveText(/Listening/);
  // "Is ..." (pause) "... it okay if I explain my week first?"
  await emit(page, 'user.speak_started');
  await emit(page, 'user.speak_ended');
  await emit(page, 'user.transcription', { text: 'Is' });
  await page.waitForTimeout(1500); // longer than a normal end-of-turn pause, shorter than the fragment wait
  expect(calls.answers).toEqual([]);
  await emit(page, 'user.speak_started');
  await emit(page, 'user.speak_ended');
  await emit(page, 'user.transcription', { text: 'it okay if I explain my week first?' });
  await expect.poll(() => calls.answers).toEqual(['Is it okay if I explain my week first?']);
});

test('a lost response to a saved answer is reconciled, not left processing forever', async ({ page }) => {
  await installFakeLiveAvatar(page, { speakMs: 100 });
  const calls = await mockApi(page, { dropFirstAnswerResponse: true });
  await page.goto(`/discover/${LINK}/avatar`);
  await page.getByTestId('avatar-start').click();
  await expect(page.getByTestId('turn-status')).toHaveText(/Listening/);
  await emit(page, 'user.speak_started');
  await emit(page, 'user.speak_ended');
  await emit(page, 'user.transcription', { text: 'I prepare the weekly reports.' });
  // One saved answer, then the engine's next question is spoken.
  await expect.poll(async () => (await fake(page)).repeated[0].at(-1)).toBe('Weekly report: every Monday; 1 to 2 hours. Is that right?');
  expect(calls.answers).toEqual(['I prepare the weekly reports.']);
});

test('the employee can interrupt June mid-sentence', async ({ page }) => {
  await installFakeLiveAvatar(page, { speakMs: 4000 });
  const calls = await mockApi(page);
  await page.goto(`/discover/${LINK}/avatar`);
  await page.getByTestId('avatar-start').click();
  await expect.poll(async () => (await fake(page)).repeated[0]?.length ?? 0).toBe(2); // greeting done, asking Q1
  await expect(page.getByTestId('turn-status')).toHaveText('June is speaking');
  await emit(page, 'user.speak_started');
  await expect.poll(async () => (await fake(page)).interrupts).toBeGreaterThan(0);
  await expect(page.getByTestId('turn-status')).toHaveText('Listening to you…');
  // The engine is told this answer cut its question short, so it can respond naturally.
  await emit(page, 'user.speak_ended');
  await emit(page, 'user.transcription', { text: 'Sorry, I do payroll mostly.' });
  await expect.poll(() => calls.answerMeta).toEqual([{ input_mode: 'voice', interrupted_question: true }]);
});

test('a short noise while June speaks does not interrupt her', async ({ page }) => {
  await installFakeLiveAvatar(page, { speakMs: 3000 });
  await mockApi(page);
  await page.goto(`/discover/${LINK}/avatar`);
  await page.getByTestId('avatar-start').click();
  await expect.poll(async () => (await fake(page)).repeated[0]?.length ?? 0).toBe(2);
  await expect(page.getByTestId('turn-status')).toHaveText('June is speaking');
  await emit(page, 'user.speak_started');
  await emit(page, 'user.speak_ended'); // shorter than the barge-in threshold
  await page.waitForTimeout(800);
  expect((await fake(page)).interrupts).toBe(0);
});

test('an interruption with no words: June asks her question again', async ({ page }) => {
  await installFakeLiveAvatar(page, { speakMs: 4000 });
  const calls = await mockApi(page);
  await page.goto(`/discover/${LINK}/avatar`);
  await page.getByTestId('avatar-start').click();
  await expect.poll(async () => (await fake(page)).repeated[0]?.length ?? 0).toBe(2);
  await expect(page.getByTestId('turn-status')).toHaveText('June is speaking');
  await emit(page, 'user.speak_started');
  await expect.poll(async () => (await fake(page)).interrupts).toBeGreaterThan(0);
  await emit(page, 'user.speak_ended'); // a cough, a door: no transcript
  await expect.poll(async () => (await fake(page)).repeated[0], { timeout: 6000 }).toEqual([TEXTS.phrases.greeting, Q1, Q1]);
  expect(calls.answers).toEqual([]);
});

test('guard: if LiveAvatar ever speaks on its own, June is silenced and the same session carries on', async ({ page }) => {
  await installFakeLiveAvatar(page, { speakMs: 100 });
  const calls = await mockApi(page);
  await page.goto(`/discover/${LINK}/avatar`);
  await page.getByTestId('avatar-start').click();
  await expect.poll(async () => (await fake(page)).repeated[0]?.length ?? 0).toBe(2);
  await expect(page.getByTestId('turn-status')).toHaveText(/Listening/);
  const before = (await fake(page)).interrupts;

  // An improvised reply from a LiveAvatar-side LLM.
  await emit(page, 'avatar.transcription', { text: 'Sure, as your HR assistant I can explain the leave policy right now.' });
  await expect.poll(async () => (await fake(page)).interrupts).toBe(before + 1);
  // No other mode, no other avatar, no new session: the interview simply continues.
  expect(calls.sessions).toHaveLength(1);
  expect((await fake(page)).modes).toEqual(['FULL']);
  await emit(page, 'user.speak_started');
  await emit(page, 'user.speak_ended');
  await emit(page, 'user.transcription', { text: 'I mostly run payroll.' });
  await expect.poll(() => calls.answers).toEqual(['I mostly run payroll.']);
  expect(calls.external).toEqual([]);
});

test('a LiveAvatar refusal is shown with its reason and a retry; no other avatar is offered', async ({ page }) => {
  await installFakeLiveAvatar(page, { speakMs: 100 });
  const calls = await mockApi(page, { liveavatarError: 'LiveAvatar refused /v1/sessions/token (HTTP 402): Insufficient credits' });
  await page.goto(`/discover/${LINK}/avatar`);
  await page.getByTestId('avatar-start').click();
  await expect(page.getByTestId('avatar-error-reason')).toContainText('HTTP 402');
  await expect(page.getByTestId('avatar-error')).not.toContainText(/simli|voice only/i);
  expect((await fake(page)).modes).toEqual([]); // nothing started, nothing silently substituted

  await page.getByTestId('avatar-retry').click();
  await expect.poll(async () => (await fake(page)).repeated[0]).toEqual([TEXTS.phrases.greeting, Q1]);
  expect(calls.sessions).toEqual([{}, {}]);
  expect(calls.external).toEqual([]);
});

test('a dropped LiveAvatar session shows a clear error; Try again resumes where it left off', async ({ page }) => {
  await installFakeLiveAvatar(page, { speakMs: 100 });
  const calls = await mockApi(page);
  await page.goto(`/discover/${LINK}/avatar`);
  await page.getByTestId('avatar-start').click();
  await expect.poll(async () => (await fake(page)).repeated[0]?.length ?? 0).toBe(2);

  await emit(page, 'session.stopped', { stop_reason: 'MAX_DURATION_REACHED' });
  await expect(page.getByTestId('avatar-error')).toContainText('connection to June was lost');
  await expect(page.getByTestId('avatar-error-reason')).toContainText('MAX_DURATION_REACHED');
  await expect.poll(() => calls.stops).toBeGreaterThanOrEqual(1); // server-side backstop

  await page.getByTestId('avatar-retry').click();
  await expect.poll(async () => (await fake(page)).repeated[1]).toEqual([TEXTS.phrases.resumed, Q1]);
  expect(calls.sessions).toHaveLength(2);
});

test('speaking on after a pause: June waits, and the extra words are never sent to a question they did not hear', async ({ page }) => {
  await installFakeLiveAvatar(page, { speakMs: 100 });
  const calls = await mockApi(page, { replyDelayMs: 2500 });
  await page.goto(`/discover/${LINK}/avatar`);
  await page.getByTestId('avatar-start').click();
  await expect(page.getByTestId('turn-status')).toHaveText(/Listening/);
  await emit(page, 'user.speak_started');
  await emit(page, 'user.speak_ended');
  await emit(page, 'user.transcription', { text: 'I prepare the weekly reports.' });
  await expect.poll(() => calls.answers).toEqual(['I prepare the weekly reports.']);
  // They carry on talking while the engine works: the next question waits for them.
  await emit(page, 'user.speak_started');
  await emit(page, 'user.transcription', { text: 'And I also handle supplier queries.' });
  await page.waitForTimeout(1500);
  expect((await fake(page)).repeated[0]).toEqual([TEXTS.phrases.greeting, Q1]);
  await emit(page, 'user.speak_ended');
  await expect.poll(async () => (await fake(page)).repeated[0].at(-1)).toBe('Weekly report: every Monday; 1 to 2 hours. Is that right?');
  // Nothing more is sent until they actually answer the new question...
  await page.waitForTimeout(3500);
  expect(calls.answers).toHaveLength(1);
  // ...and then nothing they said is lost: the held words open their next answer.
  await emit(page, 'user.speak_started');
  await emit(page, 'user.speak_ended');
  await emit(page, 'user.transcription', { text: 'Yes, every Monday.' });
  await expect.poll(() => calls.answers).toEqual(['I prepare the weekly reports.', 'And I also handle supplier queries. Yes, every Monday.']);
});

test('silence, fillers and June\'s own words never become an answer or a new question', async ({ page }) => {
  await installFakeLiveAvatar(page, { speakMs: 100 });
  const calls = await mockApi(page);
  await page.goto(`/discover/${LINK}/avatar`);
  await page.getByTestId('avatar-start').click();
  await expect(page.getByTestId('turn-status')).toHaveText(/Listening/);
  for (const text of ['Um.', 'Thanks for watching!', '']) {
    await emit(page, 'user.speak_started');
    await emit(page, 'user.speak_ended');
    await emit(page, 'user.transcription', { text });
  }
  await emit(page, 'user.transcription', { text: Q1 }); // June's question picked up by the microphone
  await page.waitForTimeout(3500);
  expect(calls.answers).toEqual([]);
  expect((await fake(page)).repeated[0]).toEqual([TEXTS.phrases.greeting, Q1]);
});

test('a sentence left open waits for the rest, and a repeated transcript is not duplicated', async ({ page }) => {
  await installFakeLiveAvatar(page, { speakMs: 100 });
  const calls = await mockApi(page);
  await page.goto(`/discover/${LINK}/avatar`);
  await page.getByTestId('avatar-start').click();
  await expect(page.getByTestId('turn-status')).toHaveText(/Listening/);
  await emit(page, 'user.speak_started');
  await emit(page, 'user.speak_ended');
  await emit(page, 'user.transcription', { text: 'I started by checking the emails, coordinating with the hiring managers, and just' });
  await emit(page, 'user.transcription', { text: 'I started by checking the emails, coordinating with the hiring managers, and just' });
  await page.waitForTimeout(2200); // past the normal pause, within the open-sentence wait
  expect(calls.answers).toEqual([]);
  await emit(page, 'user.speak_started');
  await emit(page, 'user.speak_ended');
  await emit(page, 'user.transcription', { text: 'following up on offers.' });
  await expect.poll(() => calls.answers).toEqual([
    'I started by checking the emails, coordinating with the hiring managers, and just following up on offers.']);
});

test('paused: Continue with AI Avatar resumes; Continue with Text opens the same saved interview', async ({ page }) => {
  await installFakeLiveAvatar(page, { speakMs: 100 });
  const calls = await mockApi(page);
  await page.goto(`/discover/${LINK}/avatar`);
  await page.getByTestId('avatar-start').click();
  await expect(page.getByTestId('turn-status')).toHaveText(/Listening/);

  await page.getByTestId('avatar-pause').click();
  await expect(page.getByTestId('avatar-paused')).toBeVisible();
  await page.getByTestId('avatar-continue-avatar').click();
  await expect.poll(async () => (await fake(page)).repeated[0].slice(-2)).toEqual([TEXTS.phrases.resumed, Q1]);

  await page.getByTestId('avatar-pause').click();
  await page.getByTestId('avatar-continue-text').click();
  await expect(page).toHaveURL(new RegExp(`/discover/${LINK}/chat$`));
  await expect(page.getByText(Q1)).toBeVisible(); // the same saved conversation, same question
  await expect(page.getByText(/Reply YES|via WhatsApp/)).toHaveCount(0); // consent was given: no WhatsApp prompt
  await expect.poll(async () => calls.stops).toBeGreaterThanOrEqual(1); // the avatar session was stopped
  expect(calls.answers).toEqual([]); // nothing re-sent, nothing duplicated
  expect(calls.sessions).toHaveLength(1);
});

test('a slow or failed first read at start-up is retried, not shown as an error', async ({ page }) => {
  await installFakeLiveAvatar(page, { speakMs: 100 });
  const calls = await mockApi(page, { failFirstRead: true });
  await page.goto(`/discover/${LINK}/avatar`);
  await page.getByTestId('avatar-start').click();
  await expect.poll(async () => (await fake(page)).repeated[0]).toEqual([TEXTS.phrases.greeting, Q1]);
  await expect(page.getByTestId('avatar-error')).toHaveCount(0);
  expect(calls.sessions).toHaveLength(1);
});

test('text interview before consent still shows the consent prompt it needs', async ({ page }) => {
  await installFakeLiveAvatar(page, { speakMs: 100 });
  await mockApi(page, { awaitingConsent: true });
  await page.goto(`/discover/${LINK}/chat`);
  await expect(page.getByText(/Reply YES to continue/)).toBeVisible();
});
