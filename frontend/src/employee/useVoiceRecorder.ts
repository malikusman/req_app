import { useCallback, useEffect, useRef, useState } from 'react';

// Chrome and Firefox record WebM/Opus, Safari MP4/AAC. The first one the browser
// supports wins; the server keeps the format so transcription reads it correctly.
const CANDIDATE_TYPES = ['audio/webm;codecs=opus', 'audio/webm', 'audio/mp4', 'audio/ogg;codecs=opus'];

function pickType() {
  if (typeof MediaRecorder === 'undefined') return '';
  return CANDIDATE_TYPES.find((t) => MediaRecorder.isTypeSupported(t)) ?? '';
}

function extensionFor(type: string) {
  if (type.includes('mp4')) return 'm4a';
  if (type.includes('ogg')) return 'ogg';
  return 'webm';
}

export const voiceRecordingSupported = () =>
  typeof window !== 'undefined' && !!navigator.mediaDevices?.getUserMedia && typeof MediaRecorder !== 'undefined';

/**
 * Records one spoken answer. start() asks for the microphone; stop() resolves with
 * the recording as a File ready to upload; cancel() throws it away. Recording
 * stops by itself at maxSeconds, so a forgotten microphone does not run on.
 */
export function useVoiceRecorder({ maxSeconds = 180 }: { maxSeconds?: number } = {}) {
  const [recording, setRecording] = useState(false);
  const [seconds, setSeconds] = useState(0);
  const [error, setError] = useState('');
  const recorderRef = useRef<MediaRecorder | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const timerRef = useRef<number | null>(null);
  const finishRef = useRef<((file: File | null) => void) | null>(null);
  const discardRef = useRef(false);

  const release = useCallback(() => {
    if (timerRef.current) window.clearInterval(timerRef.current);
    timerRef.current = null;
    streamRef.current?.getTracks().forEach((t) => t.stop());
    streamRef.current = null;
    recorderRef.current = null;
    setRecording(false);
  }, []);

  const stop = useCallback(
    () =>
      new Promise<File | null>((resolve) => {
        const recorder = recorderRef.current;
        if (!recorder || recorder.state === 'inactive') {
          resolve(null);
          return;
        }
        finishRef.current = resolve;
        recorder.stop();
      }),
    []
  );

  const start = useCallback(async () => {
    setError('');
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const type = pickType();
      const recorder = type ? new MediaRecorder(stream, { mimeType: type }) : new MediaRecorder(stream);
      streamRef.current = stream;
      recorderRef.current = recorder;
      chunksRef.current = [];
      discardRef.current = false;
      recorder.ondataavailable = (e) => {
        if (e.data.size > 0) chunksRef.current.push(e.data);
      };
      recorder.onstop = () => {
        const mime = (recorder.mimeType || type || 'audio/webm').split(';')[0];
        const blob = new Blob(chunksRef.current, { type: mime });
        const file =
          discardRef.current || blob.size === 0
            ? null
            : new File([blob], `answer.${extensionFor(mime)}`, { type: mime });
        release();
        finishRef.current?.(file);
        finishRef.current = null;
      };
      recorder.start();
      setSeconds(0);
      setRecording(true);
      timerRef.current = window.setInterval(() => {
        setSeconds((s) => {
          if (s + 1 >= maxSeconds) void stop();
          return s + 1;
        });
      }, 1000);
    } catch (err) {
      release();
      setError(
        err instanceof DOMException && err.name === 'NotAllowedError'
          ? 'Microphone access was blocked. Allow it in your browser to answer out loud, or type instead.'
          : 'Could not start the microphone. You can type your answer instead.'
      );
    }
  }, [maxSeconds, release, stop]);

  const cancel = useCallback(() => {
    discardRef.current = true;
    void stop();
  }, [stop]);

  // Never leave the microphone on after the page goes away.
  useEffect(() => () => release(), [release]);

  return { recording, seconds, error, start, stop, cancel };
}
