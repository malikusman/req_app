import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { api } from '../../lib/api';
import { useReviewerToken } from '../../lib/auth';

export function ReviewerConversations() {
  const { companyId } = useParams();
  const token = useReviewerToken();
  const [conversations, setConversations] = useState<
    { id: number; employee_id: number; employee_name: string | null; status: string }[]
  >([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!token || !companyId) return;
    api
      .reviewerConversations(token, Number(companyId))
      .then((d) => setConversations(d.conversations))
      .finally(() => setLoading(false));
  }, [token, companyId]);

  if (loading) return <p>Loading…</p>;

  return (
    <div>
      <Link to={`/reviewer/companies/${companyId}`}>← Company</Link>
      <h1>Discovery conversations</h1>
      <div className="card">
        <table>
          <thead>
            <tr>
              <th>Employee</th>
              <th>Status</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {conversations.map((c) => (
              <tr key={c.id}>
                <td>{c.employee_name || `Employee #${c.employee_id}`}</td>
                <td>{c.status}</td>
                <td>
                  <Link to={`/reviewer/companies/${companyId}/conversations/${c.id}`}>View</Link>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
