import { useCallback, useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { vehiclesApi, errorMessage, fileHref, DOC_LABELS } from './vehiclesApi';
import { StatusBadge } from './StatusBadge';
import './vehicles.css';

/** SCRUM-55/56: vehicle + owner + document previews, approve/reject, activate/deactivate. */
export default function VehicleDetailPage() {
  const { id } = useParams();
  const [vehicle, setVehicle] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState(null);
  const [docDecisions, setDocDecisions] = useState({}); // { [docId]: 'ACCEPTED' | 'REJECTED' }
  const [reason, setReason] = useState('');

  const load = useCallback(() => {
    setLoading(true);
    setError(null);
    vehiclesApi
      .get(id)
      .then((res) => {
        setVehicle(res.data);
        setDocDecisions({});
        setReason('');
      })
      .catch((err) => setError(errorMessage(err)))
      .finally(() => setLoading(false));
  }, [id]);

  useEffect(load, [load]);

  const run = async (call, successText) => {
    setBusy(true);
    setNotice(null);
    try {
      const res = await call();
      setNotice({ ok: true, text: successText });
      if (res?.data?.documents) {
        setVehicle(res.data);
        setDocDecisions({});
        setReason('');
      } else load();
    } catch (err) {
      setNotice({ ok: false, text: errorMessage(err) });
    } finally {
      setBusy(false);
    }
  };

  const documentsPayload = () =>
    Object.entries(docDecisions).map(([docId, status]) => ({ id: docId, status }));

  const approve = () =>
    run(() => vehiclesApi.decide(id, { decision: 'APPROVE', documents: documentsPayload() }), 'Vehicle approved');

  const reject = () => {
    if (reason.trim().length < 3) {
      setNotice({ ok: false, text: 'Write a reason for the driver (min 3 characters).' });
      return;
    }
    run(
      () => vehiclesApi.decide(id, { decision: 'REJECT', reason: reason.trim(), documents: documentsPayload() }),
      'Vehicle rejected'
    );
  };

  const toggleActive = () => {
    const activate = !vehicle.isActive;
    const why = activate ? '' : window.prompt('Reason for deactivating this vehicle?');
    if (!activate && (!why || why.trim().length < 3)) return;
    run(
      () => vehiclesApi.setStatus(id, activate ? { isActive: true } : { isActive: false, reason: why.trim() }),
      activate ? 'Vehicle activated' : 'Vehicle deactivated'
    );
  };

  if (loading && !vehicle) return <div className="vh-page vh-muted">Loading…</div>;
  if (error) {
    return (
      <div className="vh-page">
        <div className="vh-error">{error}</div>
        <button onClick={load}>Retry</button>
      </div>
    );
  }
  if (!vehicle) return null;

  const pending = vehicle.verificationStatus === 'PENDING';
  const owner = vehicle.owner || {};

  return (
    <div className="vh-page">
      <Link to="/vehicles">← Back to vehicles</Link>
      <div className="vh-header">
        <h1>{vehicle.plateNumber}</h1>
        <StatusBadge status={vehicle.verificationStatus} />
        <span className={vehicle.isActive ? 'vh-active' : 'vh-inactive'}>{vehicle.isActive ? 'Active' : 'Inactive'}</span>
      </div>

      {notice && <div className={notice.ok ? 'vh-ok' : 'vh-error'}>{notice.text}</div>}

      <div className="vh-grid">
        <section className="vh-card">
          <h2>Vehicle</h2>
          <dl>
            <dt>Type</dt><dd>{vehicle.vehicleType}</dd>
            <dt>Make / model</dt><dd>{vehicle.make} {vehicle.model}</dd>
            <dt>Year</dt><dd>{vehicle.year}</dd>
            <dt>Colour</dt><dd>{vehicle.color}</dd>
            <dt>Seats</dt><dd>{vehicle.totalSeats} total · {vehicle.passengerSeats} for passengers</dd>
            <dt>Cargo</dt><dd>{vehicle.cargoCapacityKg} kg · {vehicle.cargoVolumeL} L</dd>
            {vehicle.rejectionReason && (<><dt>Last rejection</dt><dd>{vehicle.rejectionReason}</dd></>)}
          </dl>
        </section>
        <section className="vh-card">
          <h2>Owner</h2>
          <dl>
            <dt>Name</dt><dd>{owner.fullName}</dd>
            <dt>Phone</dt><dd>{owner.phone}</dd>
            <dt>Driver verification</dt>
            <dd>{owner.driverVerificationStatus ? <StatusBadge status={owner.driverVerificationStatus} /> : '—'}</dd>
          </dl>
        </section>
      </div>

      <h2>Documents</h2>
      {vehicle.missingDocuments?.length > 0 && (
        <div className="vh-warn">Missing / rejected: {vehicle.missingDocuments.map((t) => DOC_LABELS[t] ?? t).join(', ')}</div>
      )}
      <div className="vh-docs">
        {vehicle.documents.length === 0 && <div className="vh-muted">No documents uploaded.</div>}
        {vehicle.documents.map((doc) => {
          const href = fileHref(doc.fileUrl);
          // fileUrl is a signed link, so the extension comes before the query string.
          const isPdf = doc.fileUrl.split('?')[0].toLowerCase().endsWith('.pdf');
          const decision = docDecisions[doc.id];
          return (
            <div key={doc.id} className="vh-doc">
              <a href={href} target="_blank" rel="noreferrer" className="vh-preview">
                {isPdf ? <div className="vh-pdf">PDF – open</div> : <img src={href} alt={doc.docType} />}
              </a>
              <div className="vh-doc-title">{DOC_LABELS[doc.docType] ?? doc.docType}</div>
              <StatusBadge status={decision ?? doc.status} />
              {pending && (
                <div className="vh-doc-actions">
                  <button
                    className={decision === 'ACCEPTED' ? 'selected' : ''}
                    onClick={() => setDocDecisions((d) => ({ ...d, [doc.id]: 'ACCEPTED' }))}
                  >
                    Accept
                  </button>
                  <button
                    className={decision === 'REJECTED' ? 'selected danger' : 'danger'}
                    onClick={() => setDocDecisions((d) => ({ ...d, [doc.id]: 'REJECTED' }))}
                  >
                    Reject
                  </button>
                </div>
              )}
            </div>
          );
        })}
      </div>

      {pending && (
        <section className="vh-card vh-decision">
          <h2>Decision</h2>
          <textarea
            placeholder="Reason (required to reject; shown to the driver)"
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            rows={3}
          />
          <div className="vh-actions">
            <button className="primary" disabled={busy} onClick={approve}>Approve</button>
            <button className="danger" disabled={busy} onClick={reject}>Reject</button>
          </div>
        </section>
      )}

      <section className="vh-card">
        <h2>Availability</h2>
        <p className="vh-muted">
          Deactivating blocks the vehicle from new trips. It is refused while the vehicle has scheduled or
          in-progress trips. The driver cannot re-activate a vehicle an admin deactivated.
        </p>
        <button className={vehicle.isActive ? 'danger' : 'primary'} disabled={busy} onClick={toggleActive}>
          {vehicle.isActive ? 'Deactivate vehicle' : 'Activate vehicle'}
        </button>
      </section>
    </div>
  );
}
