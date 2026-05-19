import {
  Badge,
  Button,
  Card,
  EmptyState,
  Input,
  ProgressBar,
  StatCard,
  StrengthBar,
  Tabs,
} from '../components/ui';
import { Inbox } from 'lucide-react';
import { useState } from 'react';

/** Temporary design system preview — remove route before production if desired. */
export function DevUiShowcase() {
  const [tab, setTab] = useState('a');
  return (
    <div className="min-h-screen bg-surface-muted p-8">
      <h1 className="font-display text-page-title text-text-primary">UI showcase</h1>
      <p className="text-text-secondary">Design tokens and shared components at /dev/ui</p>

      <div className="mt-8 grid gap-6 md:grid-cols-3">
        <StatCard label="Companies" value={42} />
        <StatCard label="Readiness" value="72%" />
        <Card title="Card">
          <StrengthBar strength={0.65} label="Sample signal" />
          <ProgressBar value={65} className="mt-4" />
        </Card>
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
        <EmptyState icon={Inbox} title="No data" description="Example empty state." action={{ label: 'Action', onClick: () => {} }} />
      </div>
    </div>
  );
}
