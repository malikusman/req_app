// Mocked check of the Simli voice adapter (src/employee/avatar/avatarVoice.ts).
// No network, no Simli or OpenAI session: 'simli-client' is replaced by a stub and
// fetch returns synthetic PCM. Run: node scripts/simli-voice-check.mjs
import { build } from 'esbuild';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const dir = mkdtempSync(join(tmpdir(), 'simli-check-'));
const stub = join(dir, 'simli-stub.mjs');
writeFileSync(stub, `
export const LogLevel = { ERROR: 'error' };
export class SimliClient {
  constructor(token, video, audio) { this.token = token; this.sent = []; this.cleared = 0; this.handlers = {}; this.stopped = false; (globalThis.__simliInstances ??= []).push(this); }
  on(name, fn) { this.handlers[name] = fn; }
  emit(name, arg) { this.handlers[name]?.(arg); }
  async start() { if (this.token === 'bad') throw new Error('refused'); }
  sendAudioData(chunk) { this.sent.push(chunk); }
  ClearBuffer() { this.cleared += 1; }
  async stop() { this.stopped = true; }
}
`);
const out = join(dir, 'avatarVoice.mjs');
await build({
  entryPoints: [join(root, 'src/employee/avatar/avatarVoice.ts')],
  bundle: true, format: 'esm', platform: 'neutral', outfile: out, logLevel: 'error',
  alias: { 'simli-client': stub },
});
const { AvatarVoice } = await import(pathToFileURL(out).href);
const SimliClient = { get instances() { return globalThis.__simliInstances ?? []; } };

// Synthetic 24 kHz PCM16 served in irregular pieces; `gate` can hold the stream open.
const routes = new Map();
globalThis.fetch = async (url, init) => {
  const route = routes.get(url);
  if (!route) return { ok: false, status: 404, body: null };
  assert.equal(init.headers.Authorization, 'Bearer jwt-1');
  const pieces = route.pieces;
  let i = 0;
  return {
    ok: true,
    body: { getReader: () => ({ read: async () => {
      if (route.gate && i === route.gateAt) await route.gate;
      if (init.signal.aborted) return { done: true };
      return i < pieces.length ? { done: false, value: pieces[i++] } : { done: true };
    } }) },
  };
};
const pcm = (samples, split = [3001, 7777]) => {
  const bytes = new Uint8Array(samples * 2);
  for (let s = 0; s < samples; s += 1) new DataView(bytes.buffer).setInt16(s * 2, Math.round(8000 * Math.sin(s / 10)), true);
  const pieces = []; let at = 0, k = 0;
  while (at < bytes.length) { const n = split[k++ % split.length]; pieces.push(bytes.subarray(at, at + n)); at += n; }
  return pieces;
};

let passed = 0;
const check = async (name, fn) => { await fn(); passed += 1; console.log(`ok - ${name}`); };

await check('connects the avatar with the server-issued session token only', async () => {
  const v = new AvatarVoice();
  await v.connectAvatar('session-token', {}, {});
  assert.equal(v.mode, 'avatar');
  assert.equal(SimliClient.instances.at(-1).token, 'session-token');
  const bad = new AvatarVoice();
  await assert.rejects(bad.connectAvatar('bad', {}, {}), /refused/);
  assert.equal(bad.mode, 'audio');
});

await check('streams 24 kHz speech to Simli as 16 kHz PCM16 in 6000-byte chunks', async () => {
  const v = new AvatarVoice();
  await v.connectAvatar('t', {}, {});
  const client = SimliClient.instances.at(-1);
  routes.set('/speech/1', { pieces: pcm(24000) }); // 1 s of audio
  const r = await v.speak('/speech/1', 'jwt-1');
  assert.equal(r.interrupted, false);
  assert.ok(r.firstAudioAt !== null);
  const sizes = client.sent.map((c) => c.length);
  assert.ok(sizes.slice(0, -1).every((n) => n === 6000), `chunk sizes ${sizes}`);
  const total = sizes.reduce((a, b) => a + b, 0);
  assert.ok(Math.abs(total - 32000) <= 8, `16 kHz output bytes ${total}`); // 16000 samples x 2
});

await check('queues utterances in order so an acknowledgement is not cut off', async () => {
  const v = new AvatarVoice();
  await v.connectAvatar('t', {}, {});
  const client = SimliClient.instances.at(-1);
  let release; const gate = new Promise((r) => { release = r; });
  routes.set('/ack', { pieces: pcm(9000), gate, gateAt: 1 });
  routes.set('/question', { pieces: pcm(9000) });
  const order = [];
  const a = v.speak('/ack', 'jwt-1').then(() => order.push('ack'));
  const q = v.speak('/question', 'jwt-1').then(() => order.push('question'));
  await new Promise((r) => setTimeout(r, 20));
  const sentWhileAckOpen = client.sent.length;
  release();
  await Promise.all([a, q]);
  assert.deepEqual(order, ['ack', 'question']);
  assert.ok(client.sent.length > sentWhileAckOpen);
});

await check('interrupt clears the Simli buffer and drops queued speech', async () => {
  const v = new AvatarVoice();
  await v.connectAvatar('t', {}, {});
  const client = SimliClient.instances.at(-1);
  const speaking = [];
  v.onSpeaking = (s) => speaking.push(s);
  let release; const gate = new Promise((r) => { release = r; });
  routes.set('/long', { pieces: pcm(48000), gate, gateAt: 1 });
  routes.set('/next', { pieces: pcm(9000) });
  const first = v.speak('/long', 'jwt-1');
  const second = v.speak('/next', 'jwt-1');
  await new Promise((r) => setTimeout(r, 20));
  const before = client.sent.length;
  v.interrupt();
  release();
  assert.equal((await first).interrupted, true);
  assert.equal((await second).interrupted, true);
  assert.equal(client.cleared, 1);
  assert.equal(client.sent.length, before);
  assert.equal(speaking.at(-1), false);
  // The voice keeps working after a barge-in.
  const after = await v.speak('/next', 'jwt-1');
  assert.equal(after.interrupted, false);
});

await check('a failed speech request rejects without breaking later speech', async () => {
  const v = new AvatarVoice();
  await v.connectAvatar('t', {}, {});
  await assert.rejects(v.speak('/missing', 'jwt-1'), /Speech unavailable/);
  routes.set('/ok', { pieces: pcm(4000) });
  assert.equal((await v.speak('/ok', 'jwt-1')).interrupted, false);
});

await check('a Simli stop event reports the disconnect so the page falls back to voice only', async () => {
  const v = new AvatarVoice();
  await v.connectAvatar('t', {}, {});
  const reasons = [];
  v.onDisconnected = (r) => reasons.push(r);
  SimliClient.instances.at(-1).emit('stop');
  assert.equal(v.mode, 'audio');
  assert.equal(reasons.length, 1);
});

await check('close stops the Simli session', async () => {
  const v = new AvatarVoice();
  await v.connectAvatar('t', {}, {});
  const client = SimliClient.instances.at(-1);
  await v.close();
  assert.equal(client.stopped, true);
  assert.equal(v.mode, 'audio');
});

rmSync(dir, { recursive: true, force: true });
console.log(`\n${passed} passed`);
