import { useCallback, useEffect, useRef, useState } from 'react';
import { discoverApi, type DiscoverState } from './discoverApi';

const STORAGE_KEY = 'req_discover_read_aloud';

export function readAloudPreferred() {
  try {
    return localStorage.getItem(STORAGE_KEY) === '1';
  } catch {
    return false;
  }
}

export function setReadAloudPreferred(on: boolean) {
  try {
    localStorage.setItem(STORAGE_KEY, on ? '1' : '0');
  } catch {
    // Storage unavailable: the choice lasts for this page only.
  }
}

/**
 * Speaks the interviewer's questions. The server's voice when it has one
 * (state.voice.speech); the browser's own speech otherwise, or if the server's
 * cannot play. Only one thing speaks at a time, and a newer request always wins —
 * a question fetched slowly never talks over the next one.
 */
export function useReadAloud(jwt: string | null, state: DiscoverState | null) {
  const [enabled, setEnabledState] = useState(readAloudPreferred);
  const [speakingId, setSpeakingId] = useState<number | null>(null);
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const urlRef = useRef<string | null>(null);
  const requestRef = useRef(0);

  const stop = useCallback(() => {
    requestRef.current += 1;
    audioRef.current?.pause();
    audioRef.current = null;
    if (urlRef.current) URL.revokeObjectURL(urlRef.current);
    urlRef.current = null;
    if (typeof window !== 'undefined' && 'speechSynthesis' in window) window.speechSynthesis.cancel();
    setSpeakingId(null);
  }, []);

  const speak = useCallback(
    async (id: number, text: string) => {
      stop();
      if (!text.trim()) return;
      const request = requestRef.current;
      setSpeakingId(id);

      if (jwt && state?.voice?.speech) {
        try {
          const blob = await discoverApi.speech(jwt, id);
          if (request !== requestRef.current) return;
          const url = URL.createObjectURL(blob);
          urlRef.current = url;
          const audio = new Audio(url);
          audioRef.current = audio;
          audio.onended = () => setSpeakingId((current) => (current === id ? null : current));
          await audio.play();
          return;
        } catch {
          if (request !== requestRef.current) return;
          // Fall through to the browser's own voice.
        }
      }

      if (typeof window === 'undefined' || !('speechSynthesis' in window)) {
        setSpeakingId(null);
        return;
      }
      const utterance = new SpeechSynthesisUtterance(text);
      utterance.lang = state?.language || 'en';
      utterance.rate = 0.95;
      utterance.onend = () => setSpeakingId((current) => (current === id ? null : current));
      window.speechSynthesis.speak(utterance);
    },
    [jwt, state?.voice?.speech, state?.language, stop]
  );

  const setEnabled = useCallback(
    (on: boolean) => {
      setEnabledState(on);
      setReadAloudPreferred(on);
      if (!on) stop();
    },
    [stop]
  );

  useEffect(() => () => stop(), [stop]);

  return { enabled, setEnabled, speak, stop, speakingId };
}
