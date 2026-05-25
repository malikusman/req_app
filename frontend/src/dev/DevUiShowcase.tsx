import { useState } from 'react';
import { Inbox, Play } from 'lucide-react';
import {
  Badge,
  Button,
  Card,
  ChatBubble,
  EmptyState,
  Input,
  ProgressBar,
  StatCard,
  StrengthBar,
  Tabs,
} from '../components/ui';
import { StatCardGrid, StreamingChatBubble } from '../components/motion';
import { useSimulatedStream } from '../lib/useStreamingText';

const DEMO_REPLY =
  'Based on your month-end close interviews, the main bottleneck is manual reconciliation between SAP and three spreadsheet trackers. Teams spend roughly 12 hours per cycle on copy-paste handoffs.';

/** Temporary design system preview — remove route before production if desired. */
export function DevUiShowcase() {
  const [tab, setTab] = useState('a');
  const [streamDemo, setStreamDemo] = useState(false);
  const [streamKey, setStreamKey] = useState(0);
  const { text, isStreaming } = useSimulatedStream(DEMO_REPLY, {
    active: streamDemo,
    resetKey: streamKey,
  });

  const runStreamDemo = () => {
    setStreamDemo(false);
    setStreamKey((k) => k + 1);
    requestAnimationFrame(() => setStreamDemo(true));
  };

  return (
    <div className="min-h-screen bg-surface-muted p-8">
      <h1 className="font-display text-page-title text-text-primary">UI showcase</h1>
      <p className="text-text-secondary">Design tokens and shared components at /dev/ui</p>

      <Card title="AI streaming (preview)" className="mt-8 max-w-xl">
        <p className="mb-4 text-sm text-text-secondary">
          Simulates SSE token delivery — wire <code className="text-xs">useStreamingText</code> to your
          agent when ready.
        </p>
        <StreamingChatBubble
          body={streamDemo ? text : 'Press play to simulate an assistant reply…'}
          timestamp={new Date()}
          isStreaming={isStreaming}
        />
        <Button className="mt-4" icon={<Play className="h-4 w-4" />} onClick={runStreamDemo} disabled={isStreaming}>
          {isStreaming ? 'Streaming…' : 'Simulate stream'}
        </Button>
      </Card>

      <StatCardGrid className="mt-8 md:grid-cols-3">
        <StatCard label="Companies" value={42} />
        <StatCard label="Readiness" value="72%" />
        <Card title="Card">
          <StrengthBar strength={0.65} label="Sample signal" />
          <ProgressBar value={65} className="mt-4" />
        </Card>
      </StatCardGrid>

      <div className="mt-6 max-w-md space-y-3">
        <p className="text-label-caps text-text-secondary">Chat bubbles</p>
        <ChatBubble direction="inbound" body="Hello from WhatsApp." timestamp={new Date()} />
        <ChatBubble direction="outbound" body="Thanks — let's begin." timestamp={new Date()} />
      </div>

      <div className="mt-6 flex flex-wrap gap-2">
        <Badge variant="success">Active</Badge>
        <Badge variant="warning">Pending</Badge>
        <Badge variant="error">Failed</Badge>
        <Badge variant="info">Ready</Badge>
      </div>

      <div className="mt-6 flex gap-2">
        <Button>Primary</Button>
        <Button variant="secondary">Secondary</Button>
        <Button variant="ghost">Ghost</Button>
      </div>

      <div className="mt-6 max-w-sm">
        <Input label="Email" placeholder="you@company.com" />
      </div>

      <div className="mt-6">
        <Tabs
          tabs={[
            { value: 'a', label: 'Tab A' },
            { value: 'b', label: 'Tab B' },
          ]}
          value={tab}
          onChange={setTab}
        />
      </div>

      <div className="mt-6">
        <EmptyState
          icon={Inbox}
          title="No data"
          description="Example empty state."
          action={{ label: 'Action', onClick: () => {} }}
        />
      </div>
    </div>
  );
}
