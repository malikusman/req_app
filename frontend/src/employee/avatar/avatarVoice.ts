import { SimliClient, LogLevel } from 'simli-client';
import { Chunker, Pcm16Resampler } from './pcm';

const SIMLI_CHUNK_BYTES = 6000; // ~190 ms at 16 kHz PCM16, as recommended by Simli

/**
 * Speaks server-synthesised speech through the Simli avatar (lip-synced video and
 * voice), or — when the avatar cannot connect — straight to the speakers.
 * Speech is streamed: the avatar starts talking on the first chunk.
 */
export class AvatarVoice {
  private simli: SimliClient | null = null;
  private audioContext: AudioContext | null = null;
  private playhead = 0;
  private sources: AudioBufferSourceNode[] = [];
  private abort: AbortController | null = null;
  private speakingUntil = 0;
  onSpeaking: (speaking: boolean) => void = () => {};
  onDisconnected: (reason: string) => void = () => {};

  get mode(): 'avatar' | 'audio' {
    return this.simli ? 'avatar' : 'audio';
  }

  /** Resolves when the avatar's first video frame is on screen. */
  async connectAvatar(sessionToken: string, video: HTMLVideoElement, audio: HTMLAudioElement) {
    const client = new SimliClient(sessionToken, video, audio, null, LogLevel.ERROR);
    client.on('speaking', () => this.onSpeaking(true));
    client.on('silent', () => this.onSpeaking(false));
    client.on('stop', () => { this.simli = null; this.onDisconnected('The avatar session ended'); });
    client.on('error', (detail) => this.onDisconnected(detail));
    await client.start();
    this.simli = client;
  }

  /** Audio-only fallback: same voice and timing, no face. */
  useAudioOnly() {
    this.simli = null;
    this.audioContext ??= new AudioContext({ sampleRate: 24000 });
    void this.audioContext.resume();
  }

  /**
   * Streams one utterance. Resolves with the time of the first audio chunk handed
   * to the avatar/speakers (for latency measurement), after the whole utterance
   * has been queued. `interrupt()` aborts it.
   */
  speak(url: string, jwt: string): Promise<{ firstAudioAt: number | null; interrupted: boolean }> {
    // Utterances queue in order (an acknowledgement is never cut off by the next
    // question); interrupt() clears the queue.
    const generation = this.generation;
    const run = this.queue.then(() => (generation === this.generation ? this.stream(url, jwt) : { firstAudioAt: null, interrupted: true }));
    this.queue = run.catch(() => undefined);
    return run;
  }

  private queue: Promise<unknown> = Promise.resolve();
  private generation = 0;

  private async stream(url: string, jwt: string): Promise<{ firstAudioAt: number | null; interrupted: boolean }> {
    const abort = new AbortController();
    this.abort = abort;
    let firstAudioAt: number | null = null;
    const res = await fetch(url, { headers: { Authorization: `Bearer ${jwt}` }, signal: abort.signal });
    if (!res.ok || !res.body) throw new Error('Speech unavailable');
    const reader = res.body.getReader();
    const resampler = new Pcm16Resampler(24000, 16000);
    const chunker = new Chunker(SIMLI_CHUNK_BYTES);
    let carry: number | null = null;
    try {
      for (;;) {
        const { done, value } = await reader.read();
        if (done || abort.signal.aborted) break;
        if (this.simli) {
          for (const chunk of chunker.push(resampler.push(value))) {
            firstAudioAt ??= performance.now();
            this.simli.sendAudioData(chunk);
          }
        } else {
          // Audio-only: play 24 kHz directly, keeping whole samples per chunk.
          let bytes = value;
          if (carry !== null) { const j = new Uint8Array(bytes.length + 1); j[0] = carry; j.set(bytes, 1); bytes = j; carry = null; }
          if (bytes.length % 2) { carry = bytes[bytes.length - 1]; bytes = bytes.subarray(0, bytes.length - 1); }
          if (bytes.length) { firstAudioAt ??= performance.now(); this.play(bytes); }
        }
      }
      const rest = chunker.flush();
      if (rest && this.simli && !abort.signal.aborted) this.simli.sendAudioData(rest);
    } catch (err) {
      if (!abort.signal.aborted) throw err;
    }
    return { firstAudioAt, interrupted: abort.signal.aborted };
  }

  /** Barge-in: the employee started talking, so the avatar stops at once. */
  interrupt() {
    this.generation += 1;
    this.abort?.abort();
    this.simli?.ClearBuffer();
    this.sources.forEach((s) => { try { s.stop(); } catch { /* already stopped */ } });
    this.sources = [];
    if (this.audioContext) this.playhead = this.audioContext.currentTime;
    this.speakingUntil = 0;
    this.onSpeaking(false);
  }

  /** Audio-only mode has no Simli speaking/silent events; estimate from schedule. */
  get audioOnlySpeaking() {
    return !this.simli && performance.now() < this.speakingUntil;
  }

  async close() {
    this.abort?.abort();
    const client = this.simli;
    this.simli = null;
    try { await client?.stop(); } catch { /* already closed */ }
    await this.audioContext?.close().catch(() => undefined);
    this.audioContext = null;
  }

  private play(bytes: Uint8Array) {
    const ctx = this.audioContext!;
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    const buffer = ctx.createBuffer(1, bytes.length / 2, 24000);
    const data = buffer.getChannelData(0);
    for (let i = 0; i < data.length; i += 1) data[i] = view.getInt16(i * 2, true) / 32768;
    const source = ctx.createBufferSource();
    source.buffer = buffer;
    source.connect(ctx.destination);
    const startAt = Math.max(ctx.currentTime + 0.02, this.playhead);
    source.start(startAt);
    this.playhead = startAt + buffer.duration;
    this.sources.push(source);
    source.onended = () => { this.sources = this.sources.filter((s) => s !== source); if (!this.sources.length) this.onSpeaking(false); };
    this.speakingUntil = performance.now() + (this.playhead - ctx.currentTime) * 1000;
    this.onSpeaking(true);
  }
}
