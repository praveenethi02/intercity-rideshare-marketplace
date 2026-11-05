import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import Avatar from '../../components/Avatar';
import { errorMessage } from '../../lib/api';
import { useSession } from '../../lib/auth';
import StatusBadge from './StatusBadge';
import { ROLE_LABELS, usersApi } from './usersApi';
import './users.css';

function formatDate(value) {
  return value ? new Date(value).toLocaleString() : 'Not yet';
}

/** The status change the API allows for this account, or a reason why there is none. */
function statusAction(user, isSelf) {
  if (isSelf) return { note: 'You cannot change your own status.' };
  if (user.status === 'PENDING_VERIFICATION') {
    return { note: 'This user has not verified their phone yet.' };
  }
  if (user.status === 'ACTIVE') {
    return {
      status: 'SUSPENDED',
      label: 'Suspend user',
      confirm: `Suspend ${user.fullName}? They will be signed out of every device.`,
      className: 'button-danger',
    };
  }
  return {
    status: 'ACTIVE',
    label: 'Activate user',
    confirm: `Activate ${user.fullName}?`,
    className: 'button-primary',
  };
}

export default function UserDetailPage() {
  const { id } = useParams();
  const session = useSession();
  const [user, setUser] = useState(null);
  const [error, setError] = useState('');
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    const controller = new AbortController();

    usersApi
      .get(id, controller.signal)
      .then((body) => {
        setUser(body.data.user);
        setError('');
      })
      .catch((err) => {
        if (!controller.signal.aborted) setError(errorMessage(err));
      });

    return () => controller.abort();
  }, [id]);

  async function changeStatus(action) {
    if (!window.confirm(action.confirm)) return;

    setSaving(true);
    setError('');
    try {
      const body = await usersApi.setStatus(id, action.status);
      setUser(body.data.user);
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setSaving(false);
    }
  }

  const action = user && statusAction(user, user.id === session?.user?.id);

  return (
    <div className="page">
      <Link className="us-back" to="/users">
        ← Back to users
      </Link>

      {error && (
        <p className="alert us-spaced" role="alert">
          {error}
        </p>
      )}

      {!user && !error && <p className="muted">Loading user…</p>}

      {user && (
        <>
          <div className="us-heading">
            <Avatar name={user.fullName} />
            <h1>{user.fullName}</h1>
            <StatusBadge status={user.status} />
          </div>

          <dl className="us-details">
            <dt>Phone</dt>
            <dd>{user.phone}</dd>
            <dt>Email</dt>
            <dd>{user.email ?? 'Not provided'}</dd>
            <dt>Role</dt>
            <dd>{ROLE_LABELS[user.role] ?? user.role}</dd>
            <dt>Phone verified</dt>
            <dd>{formatDate(user.phoneVerifiedAt)}</dd>
            <dt>Joined</dt>
            <dd>{formatDate(user.createdAt)}</dd>
            <dt>Last updated</dt>
            <dd>{formatDate(user.updatedAt)}</dd>
          </dl>

          {action.note ? (
            <p className="muted">{action.note}</p>
          ) : (
            <button
              type="button"
              className={`button ${action.className}`}
              disabled={saving}
              onClick={() => changeStatus(action)}
            >
              {saving ? 'Saving…' : action.label}
            </button>
          )}
        </>
      )}
    </div>
  );
}
