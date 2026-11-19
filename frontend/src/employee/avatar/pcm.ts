/**
 * Streaming PCM16 helpers for the avatar voice.
 *
 * OpenAI speech streams 24 kHz mono PCM16; Simli expects 16 kHz mono PCM16. Network
 * chunks can end mid-sample, so the resampler carries leftover bytes and its
 * fractional read position across calls.
 */
export class Pcm16Resampler {
  private carryByte: number | null = null;
  private previous = 0;
  private position = 0; // read position in input samples, relative to `previous`
  private readonly step: number;

  constructor(fromRate: number, toRate: number) {
    this.step = fromRate / toRate;
  }

  /** Feed raw little-endian PCM16 bytes; returns resampled PCM16 bytes. */
  push(bytes: Uint8Array): Uint8Array {
    let data = bytes;
    if (this.carryByte !== null) {
      const joined = new Uint8Array(bytes.length + 1);
      joined[0] = this.carryByte;
      joined.set(bytes, 1);
      data = joined;
      this.carryByte = null;
    }
    if (data.length % 2 === 1) {
      this.carryByte = data[data.length - 1];
      data = data.subarray(0, data.length - 1);
    }
    const count = data.length / 2;
    if (count === 0) return new Uint8Array(0);
    const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
    const sample = (i: number) => (i < 0 ? this.previous : view.getInt16(i * 2, true));
    const out: number[] = [];
    // Positions are in this chunk's sample indices; index -1 is the last sample of
    // the previous chunk. Interpolate between floor(p) and floor(p) + 1.
    while (this.position < count - 1) {
      const base = Math.floor(this.position);
      const frac = this.position - base;
      const a = sample(base);
      const b = sample(base + 1);
      out.push(Math.round(a + (b - a) * frac));
      this.position += this.step;
    }
    this.position -= count;
    this.previous = sample(count - 1);
    const result = new Uint8Array(out.length * 2);
    const outView = new DataView(result.buffer);
    out.forEach((v, i) => outView.setInt16(i * 2, Math.max(-32768, Math.min(32767, v)), true));
    return result;
  }
}

/** Re-slices a byte stream into fixed-size chunks (Simli recommends ~6000 bytes). */
export class Chunker {
  private buffer = new Uint8Array(0);
  private readonly size: number;

  constructor(size: number) {
    this.size = size;
  }

  push(bytes: Uint8Array): Uint8Array[] {
    const joined = new Uint8Array(this.buffer.length + bytes.length);
    joined.set(this.buffer);
    joined.set(bytes, this.buffer.length);
    const chunks: Uint8Array[] = [];
    let offset = 0;
    while (joined.length - offset >= this.size) {
      chunks.push(joined.slice(offset, offset + this.size));
      offset += this.size;
    }
    this.buffer = joined.slice(offset);
    return chunks;
  }

  flush(): Uint8Array | null {
    if (!this.buffer.length) return null;
    const rest = this.buffer;
    this.buffer = new Uint8Array(0);
    return rest;
  }
}
