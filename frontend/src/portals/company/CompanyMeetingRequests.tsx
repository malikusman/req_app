import { useEffect, useMemo, useState } from 'react';
import { api, type Employee } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { PageHeader, Card, DataTable, Badge, Button, EmptyState, Textarea, Input } from '../../components/ui';
import { Sheet, SheetContent, SheetHeader, SheetTitle } from '@/components/shadcn/sheet';
import { useMediaQuery } from '../../lib/useMediaQuery';

type Meeting = {
  id: number;
  purpose: string;
  status: string;
  urgency?: string;
  duration_minutes?: number;
  desired_roles?: string[];
  reviewer_name?: string;
  admin_note?: string | null;
  scheduled_at?: string | null;
  meeting_link?: string | null;
  selected_participant_ids?: number[];
  created_at: string;
};

function statusVariant(status: string): 'info' | 'success' | 'warning' | 'error' | 'neutral' {
  if (status === 'pending_admin') return 'info';
  if (status === 'approved' || status === 'scheduled') return 'success';
  if (status === 'declined' || status === 'cancelled') return 'error';
  return 'neutral';
}

function toDatetimeLocalValue(iso?: string | null) {
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export function CompanyMeetingRequests() {
  const token = useCompanyToken();
  const isNarrow = useMediaQuery('(max-width: 1023px)');
  const [meetings, setMeetings] = useState<Meeting[]>([]);
  const [employees, setEmployees] = useState<Employee[]>([]);
  const [selected, setSelected] = useState<Meeting | null>(null);
  const [note, setNote] = useState('');
  const [scheduledAt, setScheduledAt] = useState('');
  const [meetingLink, setMeetingLink] = useState('');
  const [participantIds, setParticipantIds] = useState<number[]>([]);
  const [loading, setLoading] = useState(true);
  const [actingId, setActingId] = useState<number | null>(null);
  const [error, setError] = useState('');
  const [loadError, setLoadError] = useState('');

  const load = () => {
    if (!token) return;
    setLoadError('');
    Promise.all([api.companyMeetingRequests(token), api.companyEmployees(token)])
      .then(([m, e]) => {
        const list = m.meeting_requests as Meeting[];
        setMeetings(list);
        setEmployees(e.employees);
        setSelected((prev) => (prev ? list.find((x) => x.id === prev.id) || null : null));
      })
      .catch(() => setLoadError('Could not load meeting requests.'))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
  }, [token]);

  useEffect(() => {
    if (!selected) return;
    setNote(selected.admin_note || '');
    setScheduledAt(toDatetimeLocalValue(selected.scheduled_at));
    setMeetingLink(selected.meeting_link || '');
    setParticipantIds(selected.selected_participant_ids || []);
  }, [selected?.id]);

  const participantLabels = useMemo(() => {
    const map = new Map(employees.map((e) => [e.id, e.display_name || e.email || e.phone_e164 || `#${e.id}`]));
    return map;
  }, [employees]);

  const selectMeeting = (m: Meeting) => {
    setSelected(m);
    setError('');
  };

  const toggleParticipant = (id: number) => {
    setParticipantIds((prev) => (prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]));
  };

  const approve = async () => {
    if (!token || !selected) return;
    setActingId(selected.id);
    setError('');
    try {
      await api.approveMeetingRequest(token, selected.id, {
        admin_note: note || undefined,
        scheduled_at: scheduledAt ? new Date(scheduledAt).toISOString() : undefined,
        meeting_link: meetingLink.trim() || undefined,
        selected_participant_ids: participantIds,
      });
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Approve failed');
    } finally {
      setActingId(null);
    }
  };

  const decline = async () => {
    if (!token || !selected) return;
    setActingId(selected.id);
    setError('');
    try {
      await api.declineMeetingRequest(token, selected.id, { admin_note: note || undefined });
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Decline failed');
    } finally {
      setActingId(null);
    }
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="Meeting requests"
        description="Approve reviewer call requests and optionally set schedule, meeting link, and participants."
      />

      {error && <p className="text-sm text-status-error">{error}</p>}

      {loadError && (
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-button border border-status-error/30 bg-status-errorBg px-4 py-3 text-sm text-status-error">
          <span>{loadError}</span>
          <Button size="sm" variant="secondary" onClick={load}>
            Retry
          </Button>
        </div>
      )}

      <div className="grid gap-4 lg:grid-cols-[1fr_380px]">
        <DataTable
          loading={loading}
          onRowClick={selectMeeting}
          columns={[
            {
              key: 'reviewer',
              header: 'Reviewer',
              render: (m: Meeting) => m.reviewer_name || '—',
            },
            {
              key: 'purpose',
              header: 'Purpose',
              render: (m: Meeting) => (
                <span className="text-sm">
                  {m.purpose.slice(0, 100)}
                  {m.purpose.length > 100 ? '…' : ''}
                </span>
              ),
            },
            {
              key: 'status',
              header: 'Status',
              render: (m: Meeting) => <Badge variant={statusVariant(m.status)}>{m.status}</Badge>,
            },
            {
              key: 'when',
              header: 'When',
              render: (m: Meeting) =>
                m.scheduled_at ? (
                  <span className="text-xs text-text-secondary">{new Date(m.scheduled_at).toLocaleString()}</span>
                ) : (
                  <span className="text-xs text-text-secondary">—</span>
                ),
            },
            {
              key: 'actions',
              header: '',
              hideOnMobile: true,
              render: (m: Meeting) => (
                <Button size="sm" variant="ghost" onClick={() => selectMeeting(m)}>
                  {m.status === 'pending_admin' ? 'Review' : 'View'}
                </Button>
              ),
            },
          ]}
          rows={meetings}
          emptyState={
            <EmptyState title="No meeting requests" description="Reviewer call requests will appear here for admin approval." />
          }
        />

        <Card
          className="hidden lg:block"
          title={selected?.status === 'pending_admin' ? 'Approve meeting' : 'Meeting detail'}
        >

          {!selected ? (
            <p className="text-sm text-text-secondary">Select a request to approve, schedule, or decline.</p>
          ) : (
            <div className="space-y-4 text-sm">
              <div>
                <div className="mb-1 flex items-center gap-2">
                  <Badge variant={statusVariant(selected.status)}>{selected.status}</Badge>
                  {selected.urgency && <span className="text-xs text-text-secondary">{selected.urgency}</span>}
                </div>
                <div className="font-medium">{selected.reviewer_name || 'Reviewer'}</div>
                <p className="mt-2 whitespace-pre-wrap text-text-primary">{selected.purpose}</p>
                {!!selected.desired_roles?.length && (
                  <p className="mt-2 text-xs text-text-secondary">Roles: {selected.desired_roles.join(', ')}</p>
                )}
                {selected.duration_minutes && (
                  <p className="mt-1 text-xs text-text-secondary">Duration: {selected.duration_minutes} min</p>
                )}
              </div>

              {selected.status === 'pending_admin' ? (
                <>
                  <Input
                    label="Scheduled at (optional)"
                    type="datetime-local"
                    value={scheduledAt}
                    onChange={(e) => setScheduledAt(e.target.value)}
                  />
                  <Input
                    label="Meeting link (optional)"
                    value={meetingLink}
                    onChange={(e) => setMeetingLink(e.target.value)}
                    placeholder="https://meet.example.com/…"
                  />
                  <div>
                    <div className="mb-2 text-xs font-medium uppercase tracking-wide text-text-secondary">
                      Participants (optional)
                    </div>
                    {employees.length === 0 ? (
                      <p className="text-xs text-text-secondary">No employees available.</p>
                    ) : (
                      <ul className="max-h-40 space-y-1 overflow-auto rounded-md border border-border p-2">
                        {employees.map((e) => (
                          <li key={e.id}>
                            <label className="flex cursor-pointer items-center gap-2 text-xs">
                              <input
                                type="checkbox"
                                checked={participantIds.includes(e.id)}
                                onChange={() => toggleParticipant(e.id)}
                              />
                              <span>
                                {e.display_name || e.email || e.phone_e164}
                                {e.department ? ` · ${e.department}` : ''}
                              </span>
                            </label>
                          </li>
                        ))}
                      </ul>
                    )}
                  </div>
                  <Textarea
                    label="Admin note (optional)"
                    rows={3}
                    value={note}
                    onChange={(e) => setNote(e.target.value)}
                    placeholder="Note for the audit trail"
                  />
                  <div className="flex flex-wrap gap-2">
                    <Button size="sm" loading={actingId === selected.id} onClick={approve}>
                      {scheduledAt ? 'Approve & schedule' : 'Approve'}
                    </Button>
                    <Button size="sm" variant="secondary" loading={actingId === selected.id} onClick={decline}>
                      Decline
                    </Button>
                  </div>
                </>
              ) : (
                <div className="space-y-2 text-xs">
                  {selected.scheduled_at && (
                    <div>
                      <span className="text-text-secondary">Scheduled: </span>
                      {new Date(selected.scheduled_at).toLocaleString()}
                    </div>
                  )}
                  {selected.meeting_link && (
                    <div>
                      <span className="text-text-secondary">Link: </span>
                      <a className="text-primary hover:underline" href={selected.meeting_link} target="_blank" rel="noreferrer">
                        {selected.meeting_link}
                      </a>
                    </div>
                  )}
                  {!!selected.selected_participant_ids?.length && (
                    <div>
                      <span className="text-text-secondary">Participants: </span>
                      {selected.selected_participant_ids
                        .map((id) => participantLabels.get(id) || `#${id}`)
                        .join(', ')}
                    </div>
                  )}
                  {selected.admin_note && (
                    <div>
                      <span className="text-text-secondary">Note: </span>
                      {selected.admin_note}
                    </div>
                  )}
                </div>
              )}
            </div>
          )}
        </Card>

        <Sheet open={Boolean(selected) && isNarrow} onOpenChange={(open) => !open && setSelected(null)}>
          <SheetContent side="bottom" className="max-h-[85dvh] overflow-y-auto">
            <SheetHeader>
              <SheetTitle>
                {selected?.status === 'pending_admin' ? 'Approve meeting' : 'Meeting detail'}
              </SheetTitle>
            </SheetHeader>
            {selected ? (
              <div className="mt-4 space-y-4 text-sm">
                <div>
                  <div className="mb-1 flex items-center gap-2">
                    <Badge variant={statusVariant(selected.status)}>{selected.status}</Badge>
                    {selected.urgency && <span className="text-xs text-text-secondary">{selected.urgency}</span>}
                  </div>
                  <div className="font-medium">{selected.reviewer_name || 'Reviewer'}</div>
                  <p className="mt-2 whitespace-pre-wrap text-text-primary">{selected.purpose}</p>
                </div>
                {selected.status === 'pending_admin' ? (
                  <>
                    <Input
                      label="Scheduled at (optional)"
                      type="datetime-local"
                      value={scheduledAt}
                      onChange={(e) => setScheduledAt(e.target.value)}
                    />
                    <Input
                      label="Meeting link (optional)"
                      value={meetingLink}
                      onChange={(e) => setMeetingLink(e.target.value)}
                      placeholder="https://meet.example.com/…"
                    />
                    <Textarea
                      label="Admin note (optional)"
                      rows={3}
                      value={note}
                      onChange={(e) => setNote(e.target.value)}
                      placeholder="Note for the audit trail"
                    />
                    <div className="flex flex-wrap gap-2">
                      <Button size="sm" loading={actingId === selected.id} onClick={approve}>
                        {scheduledAt ? 'Approve & schedule' : 'Approve'}
                      </Button>
                      <Button size="sm" variant="secondary" loading={actingId === selected.id} onClick={decline}>
                        Decline
                      </Button>
                    </div>
                  </>
                ) : (
                  <div className="space-y-2 text-xs">
                    {selected.scheduled_at && (
                      <div>
                        <span className="text-text-secondary">Scheduled: </span>
                        {new Date(selected.scheduled_at).toLocaleString()}
                      </div>
                    )}
                    {selected.meeting_link && (
                      <div>
                        <span className="text-text-secondary">Link: </span>
                        <a className="text-primary hover:underline" href={selected.meeting_link} target="_blank" rel="noreferrer">
                          {selected.meeting_link}
                        </a>
                      </div>
                    )}
                    {selected.admin_note && (
                      <div>
                        <span className="text-text-secondary">Note: </span>
                        {selected.admin_note}
                      </div>
                    )}
                  </div>
                )}
              </div>
            ) : null}
          </SheetContent>
        </Sheet>
      </div>
    </div>
  );
}
