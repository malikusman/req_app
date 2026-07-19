import { useState, type FormEvent } from 'react';
import { CheckCircle2 } from 'lucide-react';
import { Modal } from '../components/ui/Modal';
import { Input } from '../components/ui/Input';
import { Select } from '../components/ui/Select';
import { Textarea } from '../components/ui/Textarea';
import { Button } from '@/components/shadcn/button';
import { api } from '@/lib/api';
import { SALES_EMAIL } from './content';

type Props = { open: boolean; onClose: () => void };

const ROLE_LABELS: Record<string, string> = {
  ops: 'Operations / Transformation',
  cto: 'CTO / Technology',
  hr: 'HR / People',
  other: 'Other',
};

export function RequestAccessModal({ open, onClose }: Props) {
  const [form, setForm] = useState({ name: '', email: '', company: '', role: 'ops', notes: '' });
  const [honeypot, setHoneypot] = useState('');
  const [status, setStatus] = useState<'idle' | 'submitting' | 'success' | 'error'>('idle');

  const handleClose = () => {
    onClose();
    if (status === 'success') {
      setForm({ name: '', email: '', company: '', role: 'ops', notes: '' });
      setStatus('idle');
    }
  };

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setStatus('submitting');
    try {
      await api.publicDemoRequest({
        name: form.name,
        email: form.email,
        company_name: form.company,
        role: ROLE_LABELS[form.role] ?? form.role,
        notes: form.notes,
        website: honeypot,
      });
      setStatus('success');
    } catch {
      setStatus('error');
    }
  };

  return (
    <Modal
      open={open}
      onClose={handleClose}
      title="Request a demo"
      footer={
        status === 'success' ? (
          <Button variant="default" onClick={handleClose}>
            Done
          </Button>
        ) : (
          <>
            <Button variant="ghost" onClick={handleClose}>
              Cancel
            </Button>
            <Button type="submit" form="request-access-form" variant="default" disabled={status === 'submitting'}>
              {status === 'submitting' ? 'Sending…' : 'Send request'}
            </Button>
          </>
        )
      }
    >
      {status === 'success' ? (
        <div className="flex flex-col items-center gap-3 py-6 text-center">
          <span className="flex h-12 w-12 items-center justify-center rounded-full bg-marketing-accent-muted">
            <CheckCircle2 className="h-6 w-6 text-marketing-accent" aria-hidden />
          </span>
          <p className="m-0 font-display text-lg font-semibold text-foreground">Request received</p>
          <p className="m-0 max-w-sm text-sm text-muted-foreground">
            Thanks, {form.name.split(' ')[0] || 'there'} — we&rsquo;ll reach out to {form.email} within one business
            day to set up your walkthrough.
          </p>
        </div>
      ) : (
        <form id="request-access-form" onSubmit={handleSubmit} className="space-y-4">
          <Input label="Full name" value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} required />
          <Input label="Work email" type="email" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} required />
          <Input label="Company" value={form.company} onChange={(e) => setForm({ ...form, company: e.target.value })} required />
          <Select
            label="Role"
            value={form.role}
            onChange={(e) => setForm({ ...form, role: e.target.value })}
            options={[
              { value: 'ops', label: ROLE_LABELS.ops },
              { value: 'cto', label: ROLE_LABELS.cto },
              { value: 'hr', label: ROLE_LABELS.hr },
              { value: 'other', label: ROLE_LABELS.other },
            ]}
          />
          <Textarea
            label="What would you like to discover? (optional)"
            value={form.notes}
            onChange={(e) => setForm({ ...form, notes: e.target.value })}
            rows={3}
          />
          {/* Honeypot — hidden from real users, bots tend to fill it. */}
          <input
            type="text"
            name="website"
            value={honeypot}
            onChange={(e) => setHoneypot(e.target.value)}
            className="hidden"
            tabIndex={-1}
            autoComplete="off"
            aria-hidden
          />
          {status === 'error' && (
            <p className="m-0 rounded-md border border-status-error/30 bg-status-errorBg px-3 py-2 text-sm text-status-error">
              Something went wrong sending your request. Please try again, or email{' '}
              <a className="font-semibold underline" href={`mailto:${SALES_EMAIL}`}>
                {SALES_EMAIL}
              </a>
              .
            </p>
          )}
        </form>
      )}
    </Modal>
  );
}
