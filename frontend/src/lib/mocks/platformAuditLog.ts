export const mockAuditLogs = [
  {
    id: 1,
    actor: 'admin@reqapp.local',
    action: 'report_approved',
    target: 'Report v2 — Acme Corp',
    created_at: '2026-05-18T16:00:00Z',
    ip: '192.168.1.1',
  },
  {
    id: 2,
    actor: 'admin@reqapp.local',
    action: 'consultant_assigned',
    target: 'consultant@reqapp.local → Acme Corp',
    created_at: '2026-05-17T10:00:00Z',
    ip: '192.168.1.1',
  },
  {
    id: 3,
    actor: 'admin@reqapp.local',
    action: 'impersonation_started',
    target: 'Acme Corp',
    created_at: '2026-05-16T11:30:00Z',
    ip: '10.0.0.5',
  },
];
