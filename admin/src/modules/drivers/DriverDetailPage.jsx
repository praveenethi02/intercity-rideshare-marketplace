import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { errorMessage } from '../../lib/api';
import { DOCUMENT_LABELS, driversApi, formatDate, REASON_MAX_LENGTH } from './driversApi';
import { StatusBadge } from './StatusBadge';
import './drivers.css';

const APPROVED = 'APPROVED';
const REJECTED = 'REJECTED';

function DocumentCard({ document }) {
  const [failed, setFailed] = useState(false);
  const label = DOCUMENT_LABELS[document.type] ?? document.type;
  // The link is signed, so the file extension comes before the query string.
  const isPdf = document.url.split('?')[0].toLowerCase().endsWith('.pdf');

  return (
    <div className="dr-doc">
      <a className="dr-preview" href={document.url} target="_blank" rel="noreferrer">
        {isPdf && <span>PDF: open</span>}
        {!isPdf && failed && <span>Could not load. Reload the documents.</span>}
        {!isPdf && !failed && <img src={document.url} alt={label} onError={() => setFailed(true)} />}
      </a>
      <strong>{label}</strong>
      <span className="muted">Uploaded {formatDate(document.uploadedAt)}</span>
    </div>
  );
}

/** SCRUM-43: a driver's details and documents, with the approve or reject decision. */
export default function DriverDetailPage() {
  const { id } = useParams();
  const [version, setVersion] = useState(0);
  const [result, setResult] = useState({ id: null, version: null, error: '', review: null });
  const [choice, setChoice] = useState(null); // The decision waiting to be confirmed.
  const [reason, setReason] = useState('');
  const [saving, setSaving] = useState(false);
  const [notice, setNotice] = useState(null);

  useEffect(() => {
    const request = new AbortController();
    driversApi
      .getReview(id, request.signal)
      .then((review) => {
        if (!request.signal.aborted) setResult({ id, version, error: '', review });
      })
      .catch((err) => {
        if (!request.signal.aborted) {
          setResult({ id, version, error: errorMessage(err), review: null });
        }
      });
    return () => request.abort();
  }, [id, version]);

  const reload = () => setVersion((count) => count + 1);

  const loaded = result.id === id;
  const refreshing = !loaded || result.version !== version;
  const review = loaded ? result.review : null;

  const cancel = () => {
    setChoice(null);
    setReason('');
  };

  const submit = async (event) => {
    event.preventDefault();
    setSaving(true);
    setNotice(null);
    try {
      const body = choice === REJECTED ? { decision: REJECTED, reason: reason.trim() } : { decision: APPROVED };
      await driversApi.decide(id, body);
      setNotice({ ok: true, text: choice === REJECTED ? 'Driver rejected.' : 'Driver approved.' });
      cancel();
    } catch (err) {
      setNotice({ ok: false, text: errorMessage(err) });
      // Another admin may have decided first, so show the current status.
      if (err?.response?.status === 409) cancel();
    } finally {
      setSaving(false);
    }
    // The decision form is at the bottom and the result is at the top.
    window.scrollTo({ top: 0 });
    reload();
  };

  const back = (
    <Link className="dr-back" to="/drivers">
      ← Back to drivers
    </Link>
  );

  if (!loaded) {
    return (
      <div className="page">
        {back}
        <p className="muted">Loading…</p>
      </div>
    );
  }

  if (result.error) {
    return (
      <div className="page">
        {back}
        <div className="alert" role="alert">
          {result.error}{' '}
          <button type="button" className="dr-link" onClick={reload}>
            Try again
          </button>
        </div>
      </div>
    );
  }

  if (!review) {
    return (
      <div className="page">
        {back}
        <div className="alert" role="alert">This verification request was not found.</div>
      </div>
    );
  }

  const { verification, user, profile } = review;
  const name = user?.fullName ?? 'this driver';

  return (
    <div className="page">
      {back}
      <div className="dr-header">
        <h1>{user?.fullName ?? 'Unknown driver'}</h1>
        <StatusBadge status={verification.status} />
      </div>

      {notice && (
        <div className={notice.ok ? 'dr-ok' : 'alert'} role={notice.ok ? 'status' : 'alert'}>
          {notice.text}
        </div>
      )}

      <div className="dr-grid">
        <section className="dr-card">
          <h2>Driver</h2>
          <dl>
            <dt>Name</dt>
            <dd>{user?.fullName ?? 'Not available'}</dd>
            <dt>Phone</dt>
            <dd>{user?.phone ?? 'Not available'}</dd>
            <dt>Email</dt>
            <dd>{user?.email ?? '—'}</dd>
            <dt>Rating</dt>
            <dd>{profile ? `${profile.averageRating.toFixed(1)} (${profile.ratingCount})` : 'Not available'}</dd>
            <dt>Completed trips</dt>
            <dd>{profile?.completedTrips ?? 'Not available'}</dd>
          </dl>
        </section>

        <section className="dr-card">
          <h2>Verification</h2>
          <dl>
            <dt>Status</dt>
            <dd><StatusBadge status={verification.status} /></dd>
            <dt>Submitted</dt>
            <dd>{formatDate(verification.submittedAt)}</dd>
            <dt>Decided</dt>
            <dd>{formatDate(verification.decidedAt)}</dd>
            {verification.reason && (
              <>
                <dt>Rejection reason</dt>
                <dd>{verification.reason}</dd>
              </>
            )}
          </dl>
        </section>
      </div>

      <div className="dr-section-title">
        <h2>Documents</h2>
        <button type="button" className="button" disabled={refreshing} onClick={reload}>
          Reload documents
        </button>
      </div>
      <p className="muted">Document links last 15 minutes. Reload them if one stops opening.</p>
      {verification.documents.length === 0 ? (
        <p className="muted">No documents uploaded.</p>
      ) : (
        <div className="dr-docs">
          {verification.documents.map((document) => (
            <DocumentCard key={`${document.id}:${document.url}`} document={document} />
          ))}
        </div>
      )}

      {verification.status === 'PENDING' && (
        <section className="dr-card dr-decision">
          <h2>Decision</h2>
          {!choice && (
            <div className="dr-actions">
              <button type="button" className="button button-primary" onClick={() => setChoice(APPROVED)}>
                Approve
              </button>
              <button type="button" className="button button-danger" onClick={() => setChoice(REJECTED)}>
                Reject
              </button>
            </div>
          )}

          {choice && (
            <form onSubmit={submit}>
              {choice === APPROVED ? (
                <p>Approve {name}? They will be able to publish trips.</p>
              ) : (
                <label className="dr-reason">
                  Why are you rejecting {name}? The driver will see this reason.
                  <textarea
                    rows={3}
                    required
                    maxLength={REASON_MAX_LENGTH}
                    value={reason}
                    onChange={(event) => setReason(event.target.value)}
                  />
                </label>
              )}
              <div className="dr-actions">
                <button
                  type="submit"
                  className={choice === APPROVED ? 'button button-primary' : 'button button-danger'}
                  disabled={saving || (choice === REJECTED && !reason.trim())}
                >
                  {choice === APPROVED ? 'Confirm approval' : 'Confirm rejection'}
                </button>
                <button type="button" className="button" disabled={saving} onClick={cancel}>
                  Cancel
                </button>
              </div>
            </form>
          )}
        </section>
      )}
    </div>
  );
}
