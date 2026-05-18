import { useCallback, useEffect, useState, type FormEvent } from 'react';
import { Link, useParams } from 'react-router-dom';
import { api, type ReportReviewPayload } from '../../lib/api';
import { useReviewerToken } from '../../lib/auth';

const SECTIONS = [
  'executive_summary',
  'readiness',
  'participation',
  'delta',
  'signals',
  'patterns',
  'recommendations',
];

export function ReviewerReportReview() {
  const { companyId, reportId } = useParams();
  const token = useReviewerToken();
  const [payload, setPayload] = useState<ReportReviewPayload | null>(null);
  const [note, setNote] = useState('');
  const [commentSection, setCommentSection] = useState(SECTIONS[0]);
  const [commentBody, setCommentBody] = useState('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const load = useCallback(() => {
    if (!token || !companyId || !reportId) return;
    api
      .reviewerReportReview(token, Number(companyId), Number(reportId))
      .then((d) => {
        setPayload(d);
        setNote(d.review.overall_note || '');
      })
      .catch((e) => setError(e instanceof Error ? e.message : 'Failed to load'))
      .finally(() => setLoading(false));
  }, [token, companyId, reportId]);

  useEffect(() => {
    load();
    const t = setInterval(load, 15000);
    return () => clearInterval(t);
  }, [load]);

  const setSectionStatus = async (sectionKey: string, status: string) => {
    if (!token || !companyId || !reportId) return;
    await api.updateSectionState(token, Number(companyId), Number(reportId), sectionKey, status);
    load();
  };

  const addComment = async (e: FormEvent) => {
    e.preventDefault();
    if (!token || !companyId || !reportId || !commentBody.trim()) return;
    await api.addReviewComment(token, Number(companyId), Number(reportId), {
      section_key: commentSection,
      body: commentBody.trim(),
    });
    setCommentBody('');
    load();
  };

  const saveNote = async () => {
    if (!token || !companyId || !reportId) return;
    await api.updateReviewerReportReview(token, Number(companyId), Number(reportId), { overall_note: note });
    load();
  };

  const submitReview = async () => {
    if (!token || !companyId || !reportId) return;
    if (!window.confirm('Submit your review? You can still view co-reviewer notes.')) return;
    await api.submitReviewerReportReview(token, Number(companyId), Number(reportId));
    load();
  };

  if (loading) return <p>Loading review…</p>;
  if (!payload) return <p>{error || 'Review not found'}</p>;

  const review = payload.review;
  const submitted = review.status === 'submitted';

  return (
    <div>
      <Link to={`/reviewer/companies/${companyId}`}>← Back to company</Link>
      <h1 style={{ marginTop: '0.5rem' }}>Report review</h1>
      <p>
        Status: <strong>{review.status}</strong>
        {review.submitted_at && ` · submitted ${new Date(review.submitted_at).toLocaleString()}`}
      </p>

      <div className="card" style={{ marginBottom: '1rem' }}>
        <h3 style={{ marginTop: 0 }}>Section progress</h3>
        {SECTIONS.map((key) => {
          const state = review.section_states.find((s) => s.section_key === key)?.status || 'not_started';
          return (
            <div key={key} style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '0.5rem' }}>
              <span style={{ width: 180 }}>{key.replace(/_/g, ' ')}</span>
              <select
                value={state}
                disabled={submitted}
                onChange={(e) => setSectionStatus(key, e.target.value)}
              >
                <option value="not_started">Not started</option>
                <option value="in_progress">In progress</option>
                <option value="reviewed">Reviewed</option>
                <option value="needs_clarification">Needs clarification</option>
              </select>
            </div>
          );
        })}
      </div>

      <div className="card" style={{ marginBottom: '1rem' }}>
        <h3 style={{ marginTop: 0 }}>Overall note</h3>
        <textarea rows={4} style={{ width: '100%' }} value={note} disabled={submitted} onChange={(e) => setNote(e.target.value)} />
        {!submitted && (
          <button type="button" className="btn btn-secondary" style={{ marginTop: '0.5rem' }} onClick={saveNote}>
            Save note
          </button>
        )}
      </div>

      <div className="card" style={{ marginBottom: '1rem' }}>
        <h3 style={{ marginTop: 0 }}>Comments</h3>
        <ul>
          {review.comments.map((c) => (
            <li key={c.id}>
              <strong>{c.section_key}</strong> ({c.reviewer_name}): {c.body}
            </li>
          ))}
        </ul>
        {!submitted && (
          <form onSubmit={addComment}>
            <select value={commentSection} onChange={(e) => setCommentSection(e.target.value)}>
              {SECTIONS.map((s) => (
                <option key={s} value={s}>
                  {s}
                </option>
              ))}
            </select>
            <input
              style={{ width: '100%', marginTop: '0.5rem' }}
              value={commentBody}
              onChange={(e) => setCommentBody(e.target.value)}
              placeholder="Add a comment…"
            />
            <button type="submit" className="btn btn-secondary" style={{ marginTop: '0.5rem' }}>
              Add comment
            </button>
          </form>
        )}
      </div>

      {payload.co_reviewer_reviews.length > 0 && (
        <div className="card" style={{ marginBottom: '1rem' }}>
          <h3 style={{ marginTop: 0 }}>Co-reviewer progress</h3>
          {payload.co_reviewer_reviews.map((cr) => (
            <div key={cr.reviewer_name} style={{ marginBottom: '1rem', borderTop: '1px solid #e2e8f0', paddingTop: '0.5rem' }}>
              <strong>{cr.reviewer_name}</strong> — {cr.status}
              <ul>
                {cr.comments.map((c, i) => (
                  <li key={i}>
                    {c.section_key}: {c.body}
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>
      )}

      {!submitted && (
        <button type="button" className="btn btn-primary" onClick={submitReview}>
          Submit review
        </button>
      )}
    </div>
  );
}
