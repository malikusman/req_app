import { useEffect, useRef, useState } from 'react';

export type StreamingStatus = 'idle' | 'streaming' | 'complete' | 'error';

/**
 * Accumulates text chunks (e.g. from SSE) and exposes streaming state.
 * When `enabled` is false, displays `fullText` immediately.
 */
export function useStreamingText({
  chunks,
  enabled = false,
  resetKey,
}: {
  chunks: string[];
  enabled?: boolean;
  /** Change to reset accumulated text (e.g. new message id). */
  resetKey?: string | number;
}) {
  const [text, setText] = useState('');
  const [status, setStatus] = useState<StreamingStatus>('idle');
  const indexRef = useRef(0);

  useEffect(() => {
    setText('');
    indexRef.current = 0;
    setStatus(enabled ? 'streaming' : 'idle');
  }, [resetKey, enabled]);

  useEffect(() => {
    if (!enabled) return;
    if (chunks.length <= indexRef.current) return;

    const next = chunks.slice(indexRef.current).join('');
    indexRef.current = chunks.length;
    setText((prev) => prev + next);
    setStatus('streaming');
  }, [chunks, enabled]);

  const complete = () => setStatus('complete');
  const fail = () => setStatus('error');
  const reset = () => {
    setText('');
    indexRef.current = 0;
    setStatus('idle');
  };

  return {
    text,
    status,
    isStreaming: status === 'streaming',
    complete,
    fail,
    reset,
  };
}

/**
 * Simulates token streaming for demos and loading states before SSE is wired.
 */
export function useSimulatedStream(
  fullText: string,
  { active, msPerChar = 18, resetKey }: { active: boolean; msPerChar?: number; resetKey?: string | number }
) {
  const [text, setText] = useState('');
  const [isStreaming, setIsStreaming] = useState(false);

  useEffect(() => {
    if (!active) {
      setText(fullText);
      setIsStreaming(false);
      return;
    }

    setText('');
    setIsStreaming(true);
    let i = 0;
    const id = window.setInterval(() => {
      i += 1;
      setText(fullText.slice(0, i));
      if (i >= fullText.length) {
        window.clearInterval(id);
        setIsStreaming(false);
      }
    }, msPerChar);

    return () => window.clearInterval(id);
  }, [active, fullText, msPerChar, resetKey]);

  return { text, isStreaming };
}
