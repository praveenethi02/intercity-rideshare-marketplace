import { useEffect, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { errorMessage } from '../../lib/api';
import { DOCUMENT_LABELS, driversApi, formatDate, STATUSES } from './driversApi';
import { StatusBadge } from './StatusBadge';
import './drivers.css';

const LIMIT = 20;
const ALL = 'ALL';
const COLUMNS = 6;
const DOCUMENT_COUNT = Object.keys(DOCUMENT_LABELS).length;

/** SCRUM-43: drivers waiting for verification, and past decisions. */
export default function DriverQueuePage() {
  const [params, setParams] = useSearchParams();
  const requested = params.get('status');
  const status = requested === ALL || STATUSES.includes(requested) ? requested : 'PENDING';
  const page = Math.max(1, Math.floor(Number(params.get('page'))) || 1);

  const [attempt, setAttempt] = useState(0);
  // The list is loading until a result for the current filter has arrived.
  const requestKey = JSON.stringify([status, page, attempt]);
  const [result, setResult] = useState({ key: null, error: '', items: [], total: 0 });
  const loading = result.key !== requestKey;
  const pages = Math.max(1, Math.ceil(result.total / LIMIT));

  useEffect(() => {
    const request = new AbortController();
    driversApi
      .listQueue({ status: status === ALL ? undefined : status, page, limit: LIMIT }, request.signal)
      .then(({ items, total }) => {
        if (!request.signal.aborted) setResult({ key: requestKey, error: '', items, total });
      })
      .catch((err) => {
        if (!request.signal.aborted) {
          setResult({ key: requestKey, error: errorMessage(err), items: [], total: 0 });
        }
      });
    return () => request.abort();
  }, [requestKey, status, page]);

  const show = (changes) => setParams({ status, ...changes });

  return (
    <div className="page">
      <h1>Drivers</h1>
      <p className="page-subtitle">Drivers appear here once they have uploaded all their documents.</p>

      <div className="dr-tabs">
        {[...STATUSES, ALL].map((option) => (
          <button
            key={option}
            type="button"
            className={option === status ? 'dr-tab active' : 'dr-tab'}
            aria-pressed={option === status}
            onClick={() => setParams({ status: option })}
          >
            {option.charAt(0) + option.slice(1).toLowerCase()}
          </button>
        ))}
      </div>

      {!loading && result.error && (
        <div className="alert" role="alert">
          {result.error}{' '}
          <button type="button" className="dr-link" onClick={() => setAttempt((count) => count + 1)}>
            Try again
          </button>
        </div>
      )}

      <div className="dr-table-wrap">
        <table className="dr-table">
          <thead>
            <tr>
              <th>Driver</th>
              <th>Phone</th>
              <th>Documents</th>
              <th>Status</th>
              <th>Submitted</th>
              <th>Decided</th>
            </tr>
          </thead>
          <tbody>
            {loading && (
              <tr>
                <td colSpan={COLUMNS} className="muted">Loading…</td>
              </tr>
            )}
            {!loading && !result.error && result.items.length === 0 && (
              <tr>
                <td colSpan={COLUMNS} className="muted">
                  {status === 'PENDING' ? 'No drivers are waiting for verification.' : 'No drivers found.'}
                </td>
              </tr>
            )}
            {!loading &&
              result.items.map(({ verification, user }) => (
                <tr key={verification.id}>
                  <td>
                    <Link to={`/drivers/${verification.id}`}>{user?.fullName ?? 'Unknown driver'}</Link>
                  </td>
                  <td>{user?.phone ?? '—'}</td>
                  <td>{verification.documents.length} of {DOCUMENT_COUNT}</td>
                  <td><StatusBadge status={verification.status} /></td>
                  <td>{formatDate(verification.submittedAt)}</td>
                  <td>{formatDate(verification.decidedAt)}</td>
                </tr>
              ))}
          </tbody>
        </table>
      </div>

      <div className="dr-pager">
        <button type="button" className="button" disabled={loading || page <= 1} onClick={() => show({ page: page - 1 })}>
          ‹ Prev
        </button>
        {!loading && !result.error && (
          <span>Page {page} of {pages} · {result.total} {result.total === 1 ? 'request' : 'requests'}</span>
        )}
        <button type="button" className="button" disabled={loading || page >= pages} onClick={() => show({ page: page + 1 })}>
          Next ›
        </button>
      </div>
    </div>
  );
}
