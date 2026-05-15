import { useEffect, useState } from 'react';
import { api, type DiscoveryQuestion } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';

export function CompanyDiscoveryQuestions() {
  const token = useCompanyToken();
  const [questions, setQuestions] = useState<DiscoveryQuestion[]>([]);
  const [error, setError] = useState('');

  const load = () => {
    if (!token) return;
    api.discoveryQuestions(token).then((d) => setQuestions(d.questions));
  };

  useEffect(() => {
    load();
  }, [token]);

  const flag = async (messageId: number, feedback: string) => {
    if (!token) return;
    setError('');
    try {
      await api.discoveryQuestionFeedback(token, messageId, feedback);
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed');
    }
  };

  return (
    <div>
      <h1 style={{ marginTop: 0 }}>Discovery questions</h1>
      <p style={{ color: '#64748b' }}>Questions employees receive during discovery — not their answers (privacy preserved).</p>
      {error && <div className="error">{error}</div>}

      <div className="card">
        <table>
          <thead>
            <tr>
              <th>When</th>
              <th>Employee</th>
              <th>Question</th>
              <th>Feedback</th>
            </tr>
          </thead>
          <tbody>
            {questions.map((q) => (
              <tr key={q.id}>
                <td>{new Date(q.created_at).toLocaleDateString()}</td>
                <td>
                  {q.employee.display_name || '—'}
                  <br />
                  <small>{q.employee.department}</small>
                </td>
                <td style={{ maxWidth: 360 }}>{q.body}</td>
                <td>
                  {q.feedback ? (
                    <span className="badge">{q.feedback}</span>
                  ) : (
                    <>
                      <button type="button" className="btn btn-secondary" style={{ marginRight: 4 }} onClick={() => flag(q.id, 'not_relevant')}>
                        Not relevant
                      </button>
                      <button type="button" className="btn btn-secondary" onClick={() => flag(q.id, 'off_track')}>
                        Off-track
                      </button>
                    </>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {questions.length === 0 && <p style={{ color: '#94a3b8' }}>No discovery questions yet.</p>}
      </div>
    </div>
  );
}
