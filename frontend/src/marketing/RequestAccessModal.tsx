import { useState, type FormEvent } from 'react';
import { Modal } from '../components/ui/Modal';
import { Input } from '../components/ui/Input';
import { Select } from '../components/ui/Select';
import { Button } from '@/components/shadcn/button';
import { useToast } from '../components/ui/ToastProvider';

type Props = { open: boolean; onClose: () => void };

export function RequestAccessModal({ open, onClose }: Props) {
  const { toast } = useToast();
  const [form, setForm] = useState({ name: '', email: '', company: '', role: 'ops' });

  const handleSubmit = (e: FormEvent) => {
    e.preventDefault();
    const subject = encodeURIComponent(`Req access request — ${form.company}`);
    const body = encodeURIComponent(
      `Name: ${form.name}\nEmail: ${form.email}\nCompany: ${form.company}\nRole: ${form.role}`
    );
    window.location.href = `mailto:sales@reqapp.local?subject=${subject}&body=${body}`;
    toast({ variant: 'success', title: 'Request prepared', description: 'Your email client should open with a pre-filled message.' });
    onClose();
  };

  return (
    <Modal open={open} onClose={onClose} title="Request access" footer={
      <>
        <Button variant="ghost" onClick={onClose}>
          Cancel
        </Button>
        <Button type="submit" form="request-access-form" variant="default">
          Send request
        </Button>
      </>
    }>
      <form id="request-access-form" onSubmit={handleSubmit} className="space-y-4">
        <Input label="Full name" value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} required />
        <Input label="Work email" type="email" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} required />
        <Input label="Company" value={form.company} onChange={(e) => setForm({ ...form, company: e.target.value })} required />
        <Select
          label="Role"
          value={form.role}
          onChange={(e) => setForm({ ...form, role: e.target.value })}
          options={[
            { value: 'ops', label: 'Operations / Transformation' },
            { value: 'cto', label: 'CTO / Technology' },
            { value: 'hr', label: 'HR / People' },
            { value: 'other', label: 'Other' },
          ]}
        />
      </form>
    </Modal>
  );
}
