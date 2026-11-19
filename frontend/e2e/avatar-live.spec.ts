import { expect, test, type Page } from '@playwright/test';
import { writeFileSync } from 'node:fs';

/**
 * LIVE end-to-end avatar interview. Skipped unless AVATAR_LIVE_URL (a fresh,
 * synthetic invite link) and OPENAI_API_KEY (test-process only, to synthesise
 * the employee's spoken answers) are set.
 *
 * Real: React page, Simli avatar (WebRTC), OpenAI Realtime transcription with
 * semantic VAD (WebRTC), Rails durable turns, Sidekiq, the Employee Discovery V2
 * engine and OpenAI speech. Simulated: only the physical microphone — the
 * employee's voice is synthetic speech injected as the getUserMedia stream, so
 * acoustic echo from speakers into a real microphone is NOT exercised.
 */
const LIVE_URL = process.env.AVATAR_LIVE_URL;
const OUT = process.env.AVATAR_LIVE_OUT;
const MAX_TURNS = Number(process.env.AVATAR_LIVE_TURNS || 40); // a short smoke run stops early
const SHOT = process.env.AVATAR_LIVE_SCREENSHOT;
test.skip(!LIVE_URL || !process.env.OPENAI_API_KEY, 'Live avatar run needs AVATAR_LIVE_URL and OPENAI_API_KEY');
test.setTimeout(45 * 60_000);

async function speech(text: string): Promise<string> {
  const res = await fetch('https://api.openai.com/v1/audio/speech', {
    method: 'POST',
    headers: { Authorization: `Bearer ${process.env.OPENAI_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: 'gpt-4o-mini-tts', voice: 'verse', input: text, response_format: 'pcm',
      instructions: 'Speak like an ordinary employee answering an interviewer: natural, a little informal.' }),
  });
  if (!res.ok) throw new Error(`test speech failed ${res.status}`);
  return Buffer.from(await res.arrayBuffer()).toString('base64');
}

/** Replace the microphone with a stream the test can speak into. */
async function injectMicrophone(page: Page) {
  await page.addInitScript(() => {
    (window as unknown as { __sttEvents: string[] }).__sttEvents = [];
    const w = window as unknown as { __mic?: { ctx: AudioContext; dest: MediaStreamAudioDestinationNode }; __micSay?: (b64: string) => Promise<number> };
    const ensure = () => {
      if (!w.__mic) {
        const ctx = new AudioContext({ sampleRate: 24000 });
        w.__mic = { ctx, dest: ctx.createMediaStreamDestination() };
      }
      return w.__mic;
    };
    navigator.mediaDevices.getUserMedia = async () => { const m = ensure(); await m.ctx.resume(); return m.dest.stream; };
    w.__micSay = async (b64: string) => {
      const m = ensure();
      const raw = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
      const view = new DataView(raw.buffer);
      const buffer = m.ctx.createBuffer(1, raw.length / 2, 24000);
      const data = buffer.getChannelData(0);
      for (let i = 0; i < data.length; i += 1) data[i] = view.getInt16(i * 2, true) / 32768;
      const src = m.ctx.createBufferSource();
      src.buffer = buffer;
      src.connect(m.dest);
      src.start();
      await new Promise((r) => { src.onended = r; });
      return buffer.duration;
    };
  });
}

let readbacks = 0;
function answerFor(question: string): string {
  const q = question.toLowerCase();
  if (/reply yes|opt out/.test(q)) return 'Yes.';
  if (/job title|your role/.test(q)) return "I'm an HR officer.";
  if (/team or department/.test(q)) return 'Human resources.';
  if (/reply ‘yes’|reply 'yes'|to finish, please/.test(q)) return 'Yes.';
  if (/here is what i captured/.test(q)) {
    readbacks += 1;
    return readbacks === 1
      ? "That's mostly right, but I forgot one thing. Once a year I update the employee handbook, and that takes two to three days."
      : "Yes, that's all correct.";
  }
  if (/to finish the estimates/.test(q)) {
    const rows = question.split('\n').filter((l) => /^\d+\./.test(l.trim()));
    return rows.map((row, i) => {
      const r = row.toLowerCase();
      const n = ['First', 'Second', 'Third', 'Fourth', 'Fifth', 'Sixth'][i];
      if (/grievance|disciplinary/.test(r)) return `${n}, I honestly can't estimate that, it varies.`;
      if (/screen|interview|chas|recruit/.test(r) && !/report|overall/.test(r)) return `${n}, that's part of my overall recruitment time.`;
      return `${n}, ${/how often/.test(r) ? 'every week, ' : ''}about thirty to forty five minutes each time.`;
    }).join(' ');
  }
  if (/which is right|which of the different/.test(q)) return 'The second one is right.';
  if (/last working day|yesterday/.test(q)) return "Okay, so yesterday I started around half eight with the HR inbox, mostly leave requests and salary certificates, that took about an hour. Then I screened CVs for two sales roles and copied the shortlisted people into my Excel tracker. Before lunch I did two phone screening interviews, and in the afternoon I chased hiring managers on WhatsApp for feedback. At the end of the day I set up a new joiner in the HRIS and then typed the same details again into the payroll spreadsheet.";
  if (/week/.test(q)) return 'Recruitment is the biggest part of my week, overall it takes me about ten to twelve hours a week, and that includes the CV screening, the phone screens and chasing the hiring managers. Every Monday I also do the recruitment status report for my manager, one to two hours.';
  if (/month|quarter/.test(q)) return 'At the end of every month I prepare the payroll input file, that takes four to six hours. Every quarter I do a headcount report, maybe three hours.';
  if (/season|annual|year|occasional/.test(q)) return 'Once a year in January I coordinate the performance reviews. And a few times a year I handle grievance cases, but how long those take really varies.';
  if (/longer/.test(q)) return 'The weekly recruitment report takes longer than it should, because I rebuild it by hand from the tracker.';
  if (/more than one place|again|twice/.test(q)) return 'New joiner details, they go into the HRIS and then again into the payroll spreadsheet.';
  if (/chase|wait/.test(q)) return 'Mostly interview feedback from hiring managers, I chase them on WhatsApp almost every day.';
  if (/check|fix|trust/.test(q)) return 'I double check the payroll input file against the HRIS because the leave balances are often wrong.';
  if (/outside|excel|whatsapp|paper/.test(q)) return 'The recruitment tracker is my own Excel file, and the chasing is all on WhatsApp.';
  if (/\bai\b|artificial|chatgpt/.test(q)) return "No, I don't use any AI tools for work.";
  if (/how often|how much|how long|time/.test(q)) return 'Every week, about thirty to forty five minutes each time.';
  return "I think that's everything for that one.";
}

test('live avatar interview: speech in, avatar speech out, engine-driven to confirmation', async ({ browser }) => {
  const context = await browser.newContext({ permissions: ['microphone'] });
  const page = await context.newPage();
  await injectMicrophone(page);
  const log: Record<string, unknown>[] = [];
  page.on('console', (m) => { if (m.type() === 'error') log.push({ console_error: m.text().slice(0, 300) }); });

  await page.goto(LIVE_URL!);
  await page.getByTestId('start-avatar').click();
  await page.getByTestId('avatar-start').click();
  const t0 = Date.now();
  await expect(page.getByTestId('mic-status')).toHaveText(/Microphone on/, { timeout: 90_000 });
  const avatar = (await page.getByTestId('avatar-status').innerText()).trim();
  log.push({ event: 'session_ready', ms: Date.now() - t0, avatar });
  const video = await page.getByTestId('avatar-video').evaluate((v: HTMLVideoElement) => ({ w: v.videoWidth, h: v.videoHeight, playing: !v.paused && v.currentTime > 0 }));
  log.push({ event: 'avatar_video', ...video });
  if (SHOT) await page.screenshot({ path: SHOT });

  const interviewer = page.locator('[data-testid="captions"] p').filter({ hasText: /^Interviewer/ });
  let lastCount = 0;
  let interruptionDone = false;
  let pauseDone = false;
  for (let turn = 1; turn <= MAX_TURNS; turn += 1) {
    if (await page.getByText(/The interview is complete/).isVisible()) break;
    // Wait for a new interviewer line and for the avatar to finish talking.
    await expect.poll(async () => interviewer.count(), { timeout: 180_000 }).toBeGreaterThan(lastCount);
    // Barge-in once, on the weekly-work question: answer while the avatar talks.
    const pending = (await interviewer.last().innerText()).replace(/^Interviewer\s*/, '');
    const bargeIn = !interruptionDone && /typical week|during a typical week|other work comes up/i.test(pending);
    if (bargeIn) {
      await expect(page.getByTestId('turn-status')).toHaveText(/Speaking/, { timeout: 60_000 });
      await page.waitForTimeout(1500);
      interruptionDone = true;
      log.push({ event: 'interrupt_attempt', turn });
    } else {
      await expect(page.getByTestId('turn-status')).toHaveText(/Listening/, { timeout: 180_000 });
      await page.waitForTimeout(400);
    }
    lastCount = await interviewer.count();
    const question = (await interviewer.last().innerText()).replace(/^Interviewer\s*/, '');
    const answer = answerFor(question);
    const audio = await speech(answer);
    if (!pauseDone && turn === 5) {
      await page.getByTestId('avatar-pause').click();
      await expect(page.getByTestId('avatar-pause')).toHaveText(/Resume/);
      await page.waitForTimeout(1500);
      await page.getByTestId('avatar-pause').click();
      pauseDone = true;
      await expect(page.getByTestId('turn-status')).toHaveText(/Listening/, { timeout: 120_000 });
      log.push({ event: 'pause_resume', turn });
    }
    const spokenAt = Date.now();
    const seconds = await page.evaluate((b64) => (window as unknown as { __micSay: (b: string) => Promise<number> }).__micSay(b64), audio);
    const answerEnd = Date.now();
    log.push({ turn, question: question.slice(0, 160), answer, answer_audio_s: Math.round(seconds * 10) / 10, spoke_ms_after_question: spokenAt - t0 });
    // The answer must appear as the employee's caption (live transcription).
    try {
      await expect(page.locator('[data-testid="captions"] p').filter({ hasText: /^You/ }).last()).toBeVisible({ timeout: 60_000 });
    } catch (err) {
      if (OUT) writeFileSync(OUT, JSON.stringify({ failed: 'no transcript', log, sttEvents: await page.evaluate(() => (window as unknown as { __sttEvents?: string[] }).__sttEvents) }, null, 1));
      throw err;
    }
    const before = lastCount;
    const done = await Promise.race([
      expect.poll(async () => interviewer.count(), { timeout: 240_000 }).toBeGreaterThan(before).then(() => 'reply'),
      page.getByText(/The interview is complete/).waitFor({ timeout: 240_000 }).then(() => 'complete'),
    ]);
    log.push({ turn, reply_visible_ms_after_answer_end: Date.now() - answerEnd, done });
    if (done === 'complete') break;
  }
  const metrics = await page.evaluate(() => (window as unknown as { __avatarMetrics?: unknown[] }).__avatarMetrics ?? []);
  const sttEvents = await page.evaluate(() => (window as unknown as { __sttEvents?: string[] }).__sttEvents ?? []);
  const captions = await page.locator('[data-testid="captions"] p').allInnerTexts();
  const completed = await page.getByText(/The interview is complete/).isVisible();
  if (OUT) writeFileSync(OUT, JSON.stringify({ completed, total_ms: Date.now() - t0, avatar, log, metrics, captions, sttEvents }, null, 1));
  if (MAX_TURNS >= 40) expect(completed).toBe(true);
  else expect(log.some((e) => e.done === 'reply')).toBe(true);
  await context.close();
});
