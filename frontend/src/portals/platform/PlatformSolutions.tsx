import { useEffect, useState } from 'react';
import { api, type SolutionCatalogEntry } from '../../lib/api';
import { usePlatformToken } from '../../lib/auth';

export function PlatformSolutions() {
  const token = usePlatformToken();
  const [solutions, setSolutions] = useState<SolutionCatalogEntry[]>([]);
  const [name, setName] = useState('');
  const [vendor, setVendor] = useState('');
  const [category, setCategory] = useState('automation');
  const [keywords, setKeywords] = useState('');

  const load = () => {
    if (!token) return;
    api.platformSolutions(token).then((d) => setSolutions(d.solutions));
  };

  useEffect(() => {
    load();
  }, [token]);

  const create = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!token) return;
    await api.createSolution(token, {
      name,
      vendor,
      category,
      match_keywords: keywords.split(',').map((k) => k.trim()).filter(Boolean),
      tags: [category],
      active: true,
    });
    setName('');
    setVendor('');
    setKeywords('');
    load();
  };

  return (
    <div>
      <h1 style={{ marginTop: 0 }}>Solution catalog</h1>
      <p style={{ color: '#64748b' }}>Curated tools matched to discovery signals in recommendations.</p>

      <div className="card" style={{ marginBottom: '1.5rem' }}>
        <h3 style={{ marginTop: 0 }}>Add solution</h3>
        <form onSubmit={create}>
          <div className="form-group">
            <label>Name</label>
            <input value={name} onChange={(e) => setName(e.target.value)} required />
          </div>
          <div className="form-group">
            <label>Vendor</label>
            <input value={vendor} onChange={(e) => setVendor(e.target.value)} />
          </div>
          <div className="form-group">
            <label>Category</label>
            <select value={category} onChange={(e) => setCategory(e.target.value)}>
              <option value="automation">automation</option>
              <option value="ai_agent">ai_agent</option>
              <option value="integration">integration</option>
              <option value="saas">saas</option>
            </select>
          </div>
          <div className="form-group">
            <label>Match keywords (comma-separated)</label>
            <input value={keywords} onChange={(e) => setKeywords(e.target.value)} placeholder="invoice, excel, approval" />
          </div>
          <button type="submit" className="btn btn-primary">
            Add
          </button>
        </form>
      </div>

      <div className="card">
        <table>
          <thead>
            <tr>
              <th>Name</th>
              <th>Category</th>
              <th>Keywords</th>
              <th>Active</th>
            </tr>
          </thead>
          <tbody>
            {solutions.map((s) => (
              <tr key={s.id}>
                <td>
                  {s.name}
                  {s.vendor ? ` · ${s.vendor}` : ''}
                </td>
                <td>{s.category}</td>
                <td>
                  <small>{s.match_keywords.join(', ')}</small>
                </td>
                <td>{s.active ? 'yes' : 'no'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
