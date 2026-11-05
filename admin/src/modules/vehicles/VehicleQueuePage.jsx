import { useEffect, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { vehiclesApi, errorMessage, STATUSES, VEHICLE_TYPES } from './vehiclesApi';
import { StatusBadge } from './StatusBadge';
import './vehicles.css';

const LIMIT = 20;

/** SCRUM-55: pending queue (default) + search/filter across all vehicles. */
export default function VehicleQueuePage() {
  const navigate = useNavigate();
  const [params, setParams] = useSearchParams();
  const status = params.get('verificationStatus') ?? 'PENDING';
  const type = params.get('type') ?? '';
  const q = params.get('q') ?? '';
  const page = Number(params.get('page') ?? 1);

  const [search, setSearch] = useState(q);
  const [state, setState] = useState({ loading: true, error: null, items: [], total: 0 });

  useEffect(() => {
    let cancelled = false;
    setState((s) => ({ ...s, loading: true, error: null }));
    vehiclesApi
      .list({
        verificationStatus: status === 'ALL' ? undefined : status,
        type: type || undefined,
        q: q || undefined,
        page,
        limit: LIMIT,
      })
      .then((res) => !cancelled && setState({ loading: false, error: null, items: res.data, total: res.meta?.total ?? 0 }))
      .catch((err) => !cancelled && setState({ loading: false, error: errorMessage(err), items: [], total: 0 }));
    return () => {
      cancelled = true;
    };
  }, [status, type, q, page]);

  const update = (changes) => {
    const next = new URLSearchParams(params);
    Object.entries(changes).forEach(([k, v]) => (v === '' || v == null ? next.delete(k) : next.set(k, v)));
    if (!('page' in changes)) next.delete('page');
    setParams(next);
  };

  const pages = Math.max(1, Math.ceil(state.total / LIMIT));

  return (
    <div className="vh-page">
      <h1>Vehicles</h1>

      <div className="vh-tabs">
        {STATUSES.map((s) => (
          <button key={s} className={s === status ? 'active' : ''} onClick={() => update({ verificationStatus: s })}>
            {s.replace('_', ' ')}
          </button>
        ))}
        <button className={status === 'ALL' ? 'active' : ''} onClick={() => update({ verificationStatus: 'ALL' })}>
          ALL
        </button>
      </div>

      <form
        className="vh-filters"
        onSubmit={(e) => {
          e.preventDefault();
          update({ q: search.trim() });
        }}
      >
        <input placeholder="Search plate, make, model, owner, phone" value={search} onChange={(e) => setSearch(e.target.value)} />
        <select value={type} onChange={(e) => update({ type: e.target.value })}>
          <option value="">All types</option>
          {VEHICLE_TYPES.map((t) => (
            <option key={t}>{t}</option>
          ))}
        </select>
        <button type="submit">Search</button>
      </form>

      {state.error && <div className="vh-error">{state.error}</div>}

      <table className="vh-table">
        <thead>
          <tr>
            <th>Plate</th>
            <th>Vehicle</th>
            <th>Type</th>
            <th>Seats</th>
            <th>Owner</th>
            <th>Status</th>
            <th>Active</th>
            <th>Updated</th>
          </tr>
        </thead>
        <tbody>
          {state.loading ? (
            <tr>
              <td colSpan={8} className="vh-muted">Loading…</td>
            </tr>
          ) : state.items.length === 0 ? (
            <tr>
              <td colSpan={8} className="vh-muted">No vehicles found.</td>
            </tr>
          ) : (
            state.items.map((v) => (
              <tr key={v.id} className="vh-row" onClick={() => navigate(`/vehicles/${v.id}`)}>
                <td><strong>{v.plateNumber}</strong></td>
                <td>{v.make} {v.model} ({v.year})</td>
                <td>{v.vehicleType}</td>
                <td>{v.passengerSeats}/{v.totalSeats}</td>
                <td>{v.owner?.fullName}<div className="vh-muted">{v.owner?.phone}</div></td>
                <td><StatusBadge status={v.verificationStatus} /></td>
                <td>{v.isActive ? 'Yes' : 'No'}</td>
                <td>{new Date(v.updatedAt).toLocaleString('en-GB', { timeZone: 'Asia/Colombo' })}</td>
              </tr>
            ))
          )}
        </tbody>
      </table>

      <div className="vh-pager">
        <button disabled={page <= 1} onClick={() => update({ page: page - 1 })}>‹ Prev</button>
        <span>Page {page} of {pages} · {state.total} vehicles</span>
        <button disabled={page >= pages} onClick={() => update({ page: page + 1 })}>Next ›</button>
      </div>
    </div>
  );
}
