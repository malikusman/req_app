import { expect, test } from '@playwright/test';
import { Chunker, Pcm16Resampler } from '../src/employee/avatar/pcm';

// Pure audio-plumbing checks (no browser, no network). They do not validate the
// live avatar experience; see avatar-live.spec.ts for the real end-to-end run.

function pcm(samples: number[]) {
  const bytes = new Uint8Array(samples.length * 2);
  const view = new DataView(bytes.buffer);
  samples.forEach((s, i) => view.setInt16(i * 2, s, true));
  return bytes;
}

function samples(bytes: Uint8Array) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  return Array.from({ length: bytes.length / 2 }, (_, i) => view.getInt16(i * 2, true));
}

test('24 kHz speech becomes 16 kHz (2/3 of the samples) with a smooth ramp preserved', () => {
  const ramp = Array.from({ length: 2400 }, (_, i) => i * 10);
  const out = samples(new Pcm16Resampler(24000, 16000).push(pcm(ramp)));
  expect(Math.abs(out.length - 1600)).toBeLessThanOrEqual(1);
  // Linear input stays linear: each output step is 1.5 input steps (15 units).
  out.slice(1, 50).forEach((v, i) => expect(v - out[i]).toBe(15));
});

test('chunks split mid-sample produce the same audio as one whole stream', () => {
  const wave = Array.from({ length: 3000 }, (_, i) => Math.round(Math.sin(i / 7) * 12000));
  const whole = samples(new Pcm16Resampler(24000, 16000).push(pcm(wave)));
  const split = new Pcm16Resampler(24000, 16000);
  const bytes = pcm(wave);
  const parts: number[] = [];
  for (let at = 0; at < bytes.length; at += 777) parts.push(...samples(split.push(bytes.subarray(at, at + 777))));
  expect(parts.length).toBe(whole.length);
  parts.forEach((v, i) => expect(Math.abs(v - whole[i])).toBeLessThanOrEqual(1));
});

test('Simli receives fixed 6000-byte chunks and the remainder on flush', () => {
  const chunker = new Chunker(6000);
  const out = [...chunker.push(new Uint8Array(4000)), ...chunker.push(new Uint8Array(9000))];
  expect(out.map((c) => c.length)).toEqual([6000, 6000]);
  expect(chunker.flush()?.length).toBe(1000);
  expect(chunker.flush()).toBeNull();
});
