import { useMemo } from 'react';
import { useParams } from 'react-router-dom';
import { LeadershipChat } from '../shared/conversation/LeadershipChat';

/**
 * A manager's conversation with leadership, by the signed link in their
 * invitation (Doc 14 §4.3): no password, no app, works on a phone. The link
 * opens this one conversation and nothing else.
 */
export function LeadershipLink() {
  const { token = '' } = useParams();
  const door = useMemo(() => ({ base: `/api/v1/public/leadership/${encodeURIComponent(token)}` }), [token]);

  return (
    <div className="flex min-h-dvh flex-col bg-background">
      <header className="shrink-0 border-b border-border bg-card/80 px-4 py-3 backdrop-blur-sm">
        <div className="mx-auto max-w-3xl">
          <h1 className="m-0 text-lg font-semibold text-foreground">Your conversation with Mjadi</h1>
          <p className="m-0 text-sm text-muted-foreground">About fifteen to twenty minutes. Pause whenever you need.</p>
        </div>
      </header>
      <main className="mx-auto flex w-full max-w-3xl flex-1 flex-col px-3 py-4 sm:px-4">
        <LeadershipChat door={door} />
      </main>
    </div>
  );
}
