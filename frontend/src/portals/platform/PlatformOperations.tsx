import { useSearchParams } from 'react-router-dom';
import { Tabs } from '../../components/ui';
import { PlatformSystem } from './PlatformSystem';
import { PlatformMonitoringPage } from './PlatformMonitoring';
import { PlatformTrials } from './PlatformTrials';
import { PlatformAuditLog } from './PlatformAuditLog';

const TABS = [
  { value: 'system', label: 'System' },
  { value: 'monitoring', label: 'Monitoring' },
  { value: 'trials', label: 'Trials' },
  { value: 'audit', label: 'Audit log' },
];

/**
 * Consolidated platform Operations area — infra health, product KPIs, expiring
 * trials, and the audit log as tabs of one surface.
 */
export function PlatformOperations() {
  const [params, setParams] = useSearchParams();
  const requested = params.get('tab');
  const tab = TABS.some((t) => t.value === requested) ? (requested as string) : 'system';
  const setTab = (value: string) => setParams({ tab: value }, { replace: true });

  return (
    <div className="space-y-6">
      <Tabs tabs={TABS} value={tab} onChange={setTab} />
      {tab === 'system' && <PlatformSystem />}
      {tab === 'monitoring' && <PlatformMonitoringPage />}
      {tab === 'trials' && <PlatformTrials />}
      {tab === 'audit' && <PlatformAuditLog />}
    </div>
  );
}
