import { useEffect, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import Avatar from '../../components/Avatar';
import { errorMessage } from '../../lib/api';
import StatusBadge from './StatusBadge';
import { ROLE_LABELS, STATUS_LABELS, usersApi } from './usersApi';
import './users.css';

export default function UsersPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const role = searchParams.get('role') ?? '';
  const status = searchParams.get('status') ?? '';
  const search = searchParams.get('search') ?? '';
  const page = Number(searchParams.get('page')) || 1;

  const [searchText, setSearchText] = useState(search);
  const [result, setResult] = useState(null);
  const [error, setError] = useState('');

  useEffect(() => {
    const controller = new AbortController();

    const params = { page };
    if (role) params.role = role;
    if (status) params.status = status;
    if (search) params.search = search;

    usersApi
      .list(params, controller.signal)
      .then((body) => {
        setResult(body);
        setError('');
      })
      .catch((err) => {
        if (!controller.signal.aborted) setError(errorMessage(err));
      });

    return () => controller.abort();
  }, [role, status, search, page]);

  /** Updates the filters in the URL and returns to the first page. */
  function applyFilter(name, value) {
    const next = new URLSearchParams(searchParams);
    if (value) next.set(name, value);
    else next.delete(name);
    next.delete('page');
    setSearchParams(next);
  }

  function goToPage(nextPage) {
    const next = new URLSearchParams(searchParams);
    next.set('page', String(nextPage));
    setSearchParams(next);
  }

  function handleSearch(event) {
    event.preventDefault();
    applyFilter('search', searchText.trim());
  }

  const users = result?.data.users ?? [];
  const meta = result?.meta;

  return (
    <div className="page">
      <h1>Users</h1>
      <p className="page-subtitle">Search accounts, review details and manage access.</p>

      <form className="us-filters" onSubmit={handleSearch}>
        <input
          type="search"
          aria-label="Search users"
          placeholder="Search by name, phone or email"
          value={searchText}
          onChange={(event) => setSearchText(event.target.value)}
        />
        <button type="submit" className="button">
          Search
        </button>
        <select
          aria-label="Filter by role"
          value={role}
          onChange={(event) => applyFilter('role', event.target.value)}
        >
          <option value="">All roles</option>
          {Object.entries(ROLE_LABELS).map(([value, label]) => (
            <option key={value} value={value}>
              {label}
            </option>
          ))}
        </select>
        <select
          aria-label="Filter by status"
          value={status}
          onChange={(event) => applyFilter('status', event.target.value)}
        >
          <option value="">All statuses</option>
          {Object.entries(STATUS_LABELS).map(([value, label]) => (
            <option key={value} value={value}>
              {label}
            </option>
          ))}
        </select>
      </form>

      {error && (
        <p className="alert" role="alert">
          {error}
        </p>
      )}

      {!result && !error && <p className="muted">Loading users…</p>}

      {result && users.length === 0 && <p className="muted">No users match these filters.</p>}

      {users.length > 0 && (
        <div className="us-table-wrap">
          <table className="us-table">
            <thead>
              <tr>
                <th>Name</th>
                <th>Phone</th>
                <th>Role</th>
                <th>Status</th>
                <th>Joined</th>
              </tr>
            </thead>
            <tbody>
              {users.map((user) => (
                <tr key={user.id}>
                  <td>
                    <Link className="us-person" to={`/users/${user.id}`}>
                      <Avatar name={user.fullName} />
                      {user.fullName}
                    </Link>
                  </td>
                  <td>{user.phone}</td>
                  <td>{ROLE_LABELS[user.role] ?? user.role}</td>
                  <td>
                    <StatusBadge status={user.status} />
                  </td>
                  <td>{new Date(user.createdAt).toLocaleDateString()}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {meta && meta.totalPages > 1 && (
        <div className="us-pager">
          <button
            type="button"
            className="button"
            disabled={meta.page <= 1}
            onClick={() => goToPage(meta.page - 1)}
          >
            Previous
          </button>
          <span className="muted">
            Page {meta.page} of {meta.totalPages} ({meta.total} users)
          </span>
          <button
            type="button"
            className="button"
            disabled={meta.page >= meta.totalPages}
            onClick={() => goToPage(meta.page + 1)}
          >
            Next
          </button>
        </div>
      )}
    </div>
  );
}
