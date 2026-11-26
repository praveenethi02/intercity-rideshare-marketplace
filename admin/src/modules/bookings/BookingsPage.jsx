import { useEffect, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { errorMessage } from '../../lib/api';
import BookingStatusBadge from './BookingStatusBadge';
import { BOOKING_STATUS_LABELS, TRIP_STATUS_LABELS, bookingsApi, formatDateTime, formatLkr } from './bookingsApi';
import './bookings.css';

/** SCRUM-231: every passenger booking, with search, filters and paging. */
export default function BookingsPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const status = searchParams.get('status') ?? '';
  const tripStatus = searchParams.get('tripStatus') ?? '';
  const search = searchParams.get('search') ?? '';
  const page = Number(searchParams.get('page')) || 1;

  const [searchText, setSearchText] = useState(search);
  const [result, setResult] = useState(null);
  const [error, setError] = useState('');

  useEffect(() => {
    const controller = new AbortController();

    const params = { page };
    if (status) params.status = status;
    if (tripStatus) params.tripStatus = tripStatus;
    if (search) params.search = search;

    bookingsApi
      .list(params, controller.signal)
      .then((body) => {
        setResult(body);
        setError('');
      })
      .catch((err) => {
        if (!controller.signal.aborted) setError(errorMessage(err));
      });

    return () => controller.abort();
  }, [status, tripStatus, search, page]);

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

  const bookings = result?.data.bookings ?? [];
  const meta = result?.meta;
  const filtered = Boolean(status || tripStatus || search);

  return (
    <div className="page">
      <h1>Bookings</h1>
      <p className="page-subtitle">Monitor passenger bookings, their trips and cancellations.</p>

      <form className="bk-filters" onSubmit={handleSearch}>
        <input
          type="search"
          aria-label="Search bookings"
          placeholder="Search by reference, passenger, phone or town"
          value={searchText}
          onChange={(event) => setSearchText(event.target.value)}
        />
        <button type="submit" className="button">
          Search
        </button>
        <select
          aria-label="Filter by booking status"
          value={status}
          onChange={(event) => applyFilter('status', event.target.value)}
        >
          <option value="">All bookings</option>
          {Object.entries(BOOKING_STATUS_LABELS).map(([value, label]) => (
            <option key={value} value={value}>
              {label}
            </option>
          ))}
        </select>
        <select
          aria-label="Filter by trip status"
          value={tripStatus}
          onChange={(event) => applyFilter('tripStatus', event.target.value)}
        >
          <option value="">All trips</option>
          {Object.entries(TRIP_STATUS_LABELS).map(([value, label]) => (
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

      {!result && !error && <p className="muted">Loading bookings…</p>}

      {result && bookings.length === 0 && (
        <p className="muted">{filtered ? 'No bookings match these filters.' : 'No bookings yet.'}</p>
      )}

      {bookings.length > 0 && (
        <div className="bk-table-wrap">
          <table className="bk-table">
            <thead>
              <tr>
                <th>Reference</th>
                <th>Passenger</th>
                <th>Ride</th>
                <th>Departure</th>
                <th>Seats</th>
                <th>Total</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              {bookings.map((booking) => (
                <tr key={booking.id}>
                  <td>
                    <Link className="bk-ref" to={`/bookings/${booking.id}`}>
                      {booking.reference}
                    </Link>
                  </td>
                  <td>
                    {booking.passenger?.fullName ?? 'Unknown'}
                    <small className="bk-sub">{booking.passenger?.phone}</small>
                  </td>
                  <td>
                    {booking.pickup.name} → {booking.drop.name}
                    <small className="bk-sub">Driver: {booking.driver?.fullName ?? 'Unknown'}</small>
                  </td>
                  <td>{formatDateTime(booking.trip.departureAt)}</td>
                  <td>{booking.seats}</td>
                  <td>{formatLkr(booking.totalCents)}</td>
                  <td>
                    <BookingStatusBadge booking={booking} />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {meta && meta.totalPages > 1 && (
        <div className="bk-pager">
          <button
            type="button"
            className="button"
            disabled={meta.page <= 1}
            onClick={() => goToPage(meta.page - 1)}
          >
            Previous
          </button>
          <span className="muted">
            Page {meta.page} of {meta.totalPages} ({meta.total} bookings)
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