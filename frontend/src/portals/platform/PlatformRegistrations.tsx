import { useEffect, useState } from 'react';
import { api, type CompanyRegistrationRow, type ConsultantApplicationRow } from '../../lib/api';
import { usePlatformToken } from '../../lib/auth';
import { PageHeader, Card, DataTable, Badge, Button, EmptyState, Textarea, Modal } from '../../components/ui';
import { EngagementSetupForm } from './EngagementSetupForm';

type PendingAction =
  | { kind: 'company'; id: number; action: 'approve' | 'reject'; label: string }
  | { kind: 'consultant'; id: number; action: 'approve' | 'reject'; label: string };

export function PlatformRegistrations() {
  const token = usePlatformToken();
  const [companies, setCompanies] = useState<CompanyRegistrationRow[]>([]);
  const [consultants, setConsultants] = useState<ConsultantApplicationRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [pending, setPending] = useState<PendingAction | null>(null);
  const [note, setNote] = useState('');
  const [acting, setActing] = useState(false);
  // Approving a company request is setting up its engagement, so it gets the
  // set-up form rather than the plain confirm dialog.
  const [approving, setApproving] = useState<CompanyRegistrationRow | null>(null);

  const load = () => {
    if (!token) return;
    setLoading(true);
    setError('');
    api
      .platformRegistrations(token, 'pending')
      .then((data) => {
        setCompanies(data.company_registrations.filter((r) => r.status === 'pending'));
        setConsultants(data.consultant_applications.filter((r) => r.status === 'pending'));
      })
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load'))
      .finally(() => setLoading(false));
  };

  useEffect(load, [token]);

  const openAction = (next: PendingAction) => {
    setPending(next);
    setNote('');
    setError('');
  };

  const closeModal = () => {
    if (acting) return;
    setPending(null);
    setNote('');
  };

  const confirmAction = async () => {
    if (!token || !pending) return;
    setActing(true);
    setError('');
    try {
      if (pending.kind === 'company') {
        await api.rejectCompanyRegistration(token, pending.id, note || undefined);
      } else {
        if (pending.action === 'approve') await api.approveConsultantApplication(token, pending.id, note || undefined);
        else await api.rejectConsultantApplication(token, pending.id, note || undefined);
      }
      setPending(null);
      setNote('');
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Action failed');
    } finally {
      setActing(false);
    }
  };

  const confirmLabel = pending?.action === 'approve' ? 'Approve' : 'Reject';

  return (
    <div className="space-y-6">
      <Modal open={!!approving} onClose={() => setApproving(null)} title="Set up engagement" className="max-w-2xl">
        {approving && token && (
          <EngagementSetupForm
            token={token}
            fromRequest
            initial={{
              company_name: approving.company_name,
              website_url: approving.website_url ?? '',
              key_user: {
                name: approving.admin_name,
                email: approving.admin_email,
                phone: approving.admin_phone ?? '',
                role_title: approving.role_title ?? '',
              },
            }}
            submitLabel="Approve and invite"
            onCancel={() => setApproving(null)}
            onSubmit={async (input) => {
              await api.approveCompanyRegistration(token, approving.id, {
                engagement: {
                  website_url: input.website_url,
                  scope_type: input.scope_type,
                  departments_in_scope: input.departments_in_scope,
                  lead_consultant_id: input.lead_consultant_id,
                  languages: input.languages,
                  proposal_reference: input.proposal_reference,
                  key_user: { role_title: input.key_user.role_title },
                },
              });
              setApproving(null);
              load();
            }}
          />
        )}
      </Modal>

      <PageHeader
        title="Registrations"
        description="Company requests become engagements once you set them up. Consultant applications are approved here too."
      />

      {error && !pending ? (
        <div className="rounded-button border border-status-error/30 bg-status-errorBg px-3 py-2 text-sm text-status-error">
          {error}
        </div>
      ) : null}

      <Card>
        <h2 className="font-display m-0 mb-4 text-lg text-text-primary">Company requests</h2>
        {loading ? (
          <p className="text-sm text-text-secondary">Loading…</p>
        ) : companies.length === 0 ? (
          <EmptyState title="No pending company requests" description="Requests from the website appear here when public sign-up is switched on." />
        ) : (
          <DataTable
            columns={[
              { key: 'company', header: 'Company', render: (r) => r.company_name },
              {
                key: 'admin',
                header: 'Admin',
                render: (r) => (
                  <div>
                    <div>{r.admin_name}</div>
                    <div className="text-xs text-text-secondary">{r.admin_email}</div>
                    {r.admin_phone ? <div className="text-xs text-text-secondary">{r.admin_phone}</div> : null}
                    {r.role_title ? <div className="text-xs text-text-secondary">{r.role_title}</div> : null}
                  </div>
                ),
              },
              {
                key: 'website',
                header: 'Website',
                render: (r) => r.website_url || <span className="text-text-secondary">—</span>,
              },
              {
                key: 'status',
                header: 'Status',
                render: (r) => <Badge variant="warning">{r.status}</Badge>,
              },
              {
                key: 'actions',
                header: '',
                render: (r) => (
                  <div className="flex gap-2">
                    <Button size="sm" onClick={() => setApproving(r)}>
                      Set up engagement
                    </Button>
                    <Button
                      size="sm"
                      variant="secondary"
                      onClick={() =>
                        openAction({ kind: 'company', id: r.id, action: 'reject', label: r.company_name })
                      }
                    >
                      Reject
                    </Button>
                  </div>
                ),
              },
            ]}
            rows={companies}
          />
        )}
      </Card>

      <Card>
        <h2 className="font-display m-0 mb-4 text-lg text-text-primary">Consultant applications</h2>
        {loading ? (
          <p className="text-sm text-text-secondary">Loading…</p>
        ) : consultants.length === 0 ? (
          <EmptyState title="No pending consultant applications" description="New applications will appear here." />
        ) : (
          <DataTable
            columns={[
              { key: 'name', header: 'Name', render: (r) => r.name },
              { key: 'email', header: 'Email', render: (r) => r.email },
              {
                key: 'expertise',
                header: 'Expertise',
                render: (r) => r.expertise_summary || r.headline || '—',
              },
              {
                key: 'actions',
                header: '',
                render: (r) => (
                  <div className="flex gap-2">
                    <Button
                      size="sm"
                      onClick={() =>
                        openAction({ kind: 'consultant', id: r.id, action: 'approve', label: r.name })
                      }
                    >
                      Approve
                    </Button>
                    <Button
                      size="sm"
                      variant="secondary"
                      onClick={() =>
                        openAction({ kind: 'consultant', id: r.id, action: 'reject', label: r.name })
                      }
                    >
                      Reject
                    </Button>
                  </div>
                ),
              },
            ]}
            rows={consultants}
          />
        )}
      </Card>

      <Modal
        open={Boolean(pending)}
        onClose={closeModal}
        title={pending ? `${confirmLabel} ${pending.kind === 'company' ? 'company' : 'consultant'}` : ''}
        footer={
          <>
            <Button variant="secondary" onClick={closeModal} disabled={acting}>
              Cancel
            </Button>
            <Button
              variant={pending?.action === 'reject' ? 'danger' : 'primary'}
              onClick={confirmAction}
              loading={acting}
            >
              {confirmLabel}
            </Button>
          </>
        }
      >
        {pending ? (
          <div className="space-y-4">
            <p className="m-0 text-sm text-text-secondary">
              {pending.action === 'approve' ? 'Approve' : 'Reject'} <strong>{pending.label}</strong>
              {pending.action === 'approve' ? ' and send a set-password email.' : '.'}
            </p>
            {error ? (
              <div className="rounded-button border border-status-error/30 bg-status-errorBg px-3 py-2 text-sm text-status-error">
                {error}
              </div>
            ) : null}
            <Textarea
              label="Review note (optional)"
              rows={3}
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder="Optional note for the audit trail"
            />
          </div>
        ) : null}
      </Modal>
    </div>
  );
}
