import { ArrowRight, Car, IdCard, RefreshCw, UserCheck, UserPlus, Users } from 'lucide-react';
import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { errorMessage } from '../../lib/api';
import { formatDate } from '../drivers/driversApi';
import StatusBadge from '../users/StatusBadge';
import { ROLE_LABELS } from '../users/usersApi';
import { loadDashboard } from './dashboardApi';
import './dashboard.css';

const STATS = [
  { key: 'users', label: 'Total users', icon: Users, to: '/users' },
  { key: 'passengers', label: 'Passengers', icon: UserCheck, to: '/users?role=PASSENGER' },
  { key: 'drivers', label: 'Drivers', icon: IdCard, to: '/users?role=DRIVER' },
  { key: 'approvedVehicles', label: 'Approved vehicles', icon: Car, to: '/vehicles?verificationStatus=APPROVED' },
];

export default function DashboardPage() {
  const [data, setData] = useState(null);
  const [error, setError] = useState(null);
  const [attempt, setAttempt] = useState(0);

  useEffect(() => {
    const request = new AbortController();
    setError(null);
    loadDashboard(request.signal)
      .then(setData)
      .catch((err) => {
        if (!request.signal.aborted) setError(errorMessage(err));
      });
    return () => request.abort();
  }, [attempt]);

  return (
    <div className="page">
      <h1>Dashboard</h1>
      <p className="page-subtitle">An overview of users, drivers and vehicles that need your attention.</p>

      {error && (
        <div className="alert db-error">
          <span>{error}</span>
          <button type="button" className="button" onClick={() => setAttempt((n) => n + 1)}>
            <RefreshCw size={16} aria-hidden="true" />
            Try again
          </button>
        </div>
      )}

      <section className="db-stats" aria-label="Key numbers">
        {STATS.map(({ key, label, icon: Icon, to }) => (
          <Link key={key} className="db-stat" to={to}>
            <span className="db-stat-icon">
              <Icon size={20} aria-hidden="true" />
            </span>
            <span className="db-stat-value">{data ? data[key] : '–'}</span>
            <span className="db-stat-label">{label}</span>
          </Link>
        ))}
      </section>

      <div className="db-columns">
        <section className="db-card">
          <h2>Needs your attention</h2>
          <Link className="db-task" to="/drivers?status=PENDING">
            <IdCard size={20} aria-hidden="true" />
            <span className="db-task-text">
              <strong>{data ? data.pendingDrivers : '–'}</strong> driver requests to review
            </span>
            <ArrowRight size={18} aria-hidden="true" />
          </Link>
          <Link className="db-task" to="/vehicles?verificationStatus=PENDING">
            <Car size={20} aria-hidden="true" />
            <span className="db-task-text">
              <strong>{data ? data.pendingVehicles : '–'}</strong> vehicles to review
            </span>
            <ArrowRight size={18} aria-hidden="true" />
          </Link>
        </section>

        <section className="db-card">
          <h2>
            <UserPlus size={18} aria-hidden="true" />
            Newest users
          </h2>
          {!data && !error && <p className="muted">Loading…</p>}
          {data && data.recentUsers.length === 0 && <p className="muted">No users yet.</p>}
          {data && data.recentUsers.length > 0 && (
            <table className="db-table">
              <thead>
                <tr>
                  <th>Name</th>
                  <th>Role</th>
                  <th>Status</th>
                  <th>Joined</th>
                </tr>
              </thead>
              <tbody>
                {data.recentUsers.map((user) => (
                  <tr key={user.id}>
                    <td>
                      <Link to={`/users/${user.id}`}>{user.fullName}</Link>
                    </td>
                    <td>{ROLE_LABELS[user.role] ?? user.role}</td>
                    <td>
                      <StatusBadge status={user.status} />
                    </td>
                    <td className="muted">{formatDate(user.createdAt)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </section>
      </div>
    </div>
  );
}