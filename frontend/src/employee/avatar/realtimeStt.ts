/**
 * Live speech-to-text with automatic turn detection (OpenAI Realtime transcription
 * over WebRTC). The browser gets only a short-lived client secret from our server.
 *
 * Events used (Realtime API, transcription session):
 *   input_audio_buffer.speech_started / speech_stopped — server/semantic VAD
 *   conversation.item.input_audio_transcription.delta / .completed — the words
 */
export type SttHandlers = {
  onSpeechStarted: () => void;
  onSpeechStopped: () => void;
  onPartial: (itemId: string, text: string) => void;
  onFinal: (itemId: string, text: string) => void;
  onState: (state: 'connecting' | 'listening' | 'closed' | 'failed', detail?: string) => void;
};

export class RealtimeStt {
  private pc: RTCPeerConnection | null = null;
  private channel: RTCDataChannel | null = null;
  private stream: MediaStream | null = null;
  private partials = new Map<string, string>();
  private readonly handlers: SttHandlers;

  constructor(handlers: SttHandlers) {
    this.handlers = handlers;
  }

  async start(clientSecret: string, webrtcUrl: string, microphone?: MediaStream) {
    this.handlers.onState('connecting');
    this.stream = microphone ?? (await navigator.mediaDevices.getUserMedia({
      audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true, channelCount: 1 },
    }));
    const pc = new RTCPeerConnection();
    this.pc = pc;
    this.stream.getAudioTracks().forEach((track) => pc.addTrack(track, this.stream!));
    const channel = pc.createDataChannel('oai-events');
    this.channel = channel;
    channel.onmessage = (event) => this.handle(event.data);
    channel.onopen = () => this.handlers.onState('listening');
    channel.onclose = () => this.handlers.onState('closed');
    pc.onconnectionstatechange = () => {
      if (pc.connectionState === 'failed') this.handlers.onState('failed', 'Speech connection failed');
    };
    const offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    const res = await fetch(webrtcUrl, {
      method: 'POST',
      body: offer.sdp,
      headers: { Authorization: `Bearer ${clientSecret}`, 'Content-Type': 'application/sdp' },
    });
    if (!res.ok) {
      this.handlers.onState('failed', `Speech service refused the connection (${res.status})`);
      throw new Error(`Speech service refused the connection (${res.status})`);
    }
    await pc.setRemoteDescription({ type: 'answer', sdp: await res.text() });
  }

  /** Stop sending microphone audio without tearing down the connection. */
  setListening(on: boolean) {
    this.stream?.getAudioTracks().forEach((track) => { track.enabled = on; });
  }

  get microphoneLive() {
    return Boolean(this.stream?.getAudioTracks().some((t) => t.enabled && t.readyState === 'live'));
  }

  close() {
    this.channel?.close();
    this.pc?.close();
    this.stream?.getTracks().forEach((t) => t.stop());
    this.pc = null;
    this.channel = null;
    this.stream = null;
  }

  private handle(raw: string) {
    let event: { type?: string; item_id?: string; delta?: string; transcript?: string; error?: { message?: string } };
    try { event = JSON.parse(raw); } catch { return; }
    // Opt-in diagnostics for tests: event types only, never transcript text.
    const trace = (window as unknown as { __sttEvents?: string[] }).__sttEvents;
    if (trace) trace.push(event.type === 'error' ? `error: ${event.error?.message ?? ''}` : String(event.type));
    switch (event.type) {
      case 'input_audio_buffer.speech_started':
        this.handlers.onSpeechStarted();
        break;
      case 'input_audio_buffer.speech_stopped':
        this.handlers.onSpeechStopped();
        break;
      case 'conversation.item.input_audio_transcription.delta': {
        const id = event.item_id || '';
        const text = (this.partials.get(id) || '') + (event.delta || '');
        this.partials.set(id, text);
        this.handlers.onPartial(id, text);
        break;
      }
      case 'conversation.item.input_audio_transcription.completed': {
        const id = event.item_id || '';
        this.partials.delete(id);
        this.handlers.onFinal(id, (event.transcript || '').trim());
        break;
      }
      case 'error':
        this.handlers.onState('failed', event.error?.message || 'Speech service error');
        break;
      default:
        break;
    }
  }
}
