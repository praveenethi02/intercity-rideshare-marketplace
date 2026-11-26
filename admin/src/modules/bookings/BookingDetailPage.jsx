import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { errorMessage } from '../../lib/api';
import BookingStatusBadge from './BookingStatusBadge';
import { TRIP_STATUS_LABELS, bookingsApi, formatDateTime, formatLkr } from './bookingsApi';
import './bookings.css';

function Person({ person }) {
  if (!person) return <dd>Unknown</dd>;
  return (
    <dd>
      <Link to={`/users/${person.id}`}>{person.fullName}</Link>
      <small className="bk-sub">{person.phone}</small>
    </dd>
  );
}

function stopNote(stop, booking) {
  const role = stop.stopOrder === booking.fromStop ? 'Pickup · ' : stop.stopOrder === booking.toStop ? 'Drop · ' : '';
  const time = stop.plannedAt ? new Date(stop.plannedAt).toLocaleTimeString() : 'No planned time';
  return role + time;
}

/** SCRUM-231: one booking with its journey, the vehicle and both people. */
export default function BookingDetailPage() {
  const { id } = useParams();
  const [booking, setBooking] = useState(null);
  const [error, setError] = useState('');

  useEffect(() => {
    const controller = new AbortController();

    bookingsApi
      .get(id, controller.signal)
      .then((body) => {
        setBooking(body.data.booking);
        setError('');
      })
      .catch((err) => {
        if (!controller.signal.aborted) setError(errorMessage(err));
      });

    return () => controller.abort();
  }, [id]);

  const trip = booking?.trip;
  const vehicle = trip?.vehicle;

  return (
    <div className="page">
      <Link className="bk-back" to="/bookings">
        ← Back to bookings
      </Link>

      {error && (
        <p className="alert bk-spaced" role="alert">
          {error}
        </p>
      )}

      {!booking && !error && <p className="muted">Loading booking…</p>}

      {booking && (
        <>
          <div className="bk-heading">
            <h1>{booking.reference}</h1>
            <BookingStatusBadge booking={booking} />
          </div>

          <div className="bk-grid">
            <section className="bk-card">
              <h2>Booking</h2>
              <dl className="bk-details">
                <dt>Passenger</dt>
                <Person person={booking.passenger} />
                <dt>Seats</dt>
                <dd>{booking.seats}</dd>
                <dt>Price per seat</dt>
                <dd>{formatLkr(booking.pricePerSeatCents)}</dd>
                <dt>Total</dt>
                <dd>{formatLkr(booking.totalCents)}</dd>
                <dt>Booked</dt>
                <dd>{formatDateTime(booking.createdAt)}</dd>
                {booking.cancelledAt && (
                  <>
                    <dt>Cancelled</dt>
                    <dd>{formatDateTime(booking.cancelledAt)}</dd>
                    <dt>Reason</dt>
                    <dd>{booking.cancelReason ?? 'No reason given'}</dd>
                  </>
                )}
              </dl>
            </section>

            <section className="bk-card">
              <h2>Trip</h2>
              <dl className="bk-details">
                <dt>Driver</dt>
                <Person person={booking.driver} />
                <dt>Route</dt>
                <dd>
                  {trip.originName} → {trip.destinationName}
                </dd>
                <dt>Trip status</dt>
                <dd>{TRIP_STATUS_LABELS[trip.status] ?? trip.status}</dd>
                <dt>Departure</dt>
                <dd>{formatDateTime(trip.departureAt)}</dd>
                {trip.startedAt && (
                  <>
                    <dt>Started</dt>
                    <dd>{formatDateTime(trip.startedAt)}</dd>
                  </>
                )}
                {trip.completedAt && (
                  <>
                    <dt>Completed</dt>
                    <dd>{formatDateTime(trip.completedAt)}</dd>
                  </>
                )}
                {trip.cancelReason && (
                  <>
                    <dt>Trip cancel reason</dt>
                    <dd>{trip.cancelReason}</dd>
                  </>
                )}
                <dt>Vehicle</dt>
                <dd>
                  {vehicle ? `${vehicle.make} ${vehicle.model} (${vehicle.year}), ${vehicle.color}` : 'Not found'}
                  {vehicle?.plateNumber && <small className="bk-sub">{vehicle.plateNumber}</small>}
                </dd>
              </dl>
            </section>
          </div>

          <section className="bk-card bk-spaced">
            <h2>Passenger route</h2>
            <ol className="bk-stops">
              {(trip.stops ?? []).map((stop) => (
                <li key={stop.stopOrder}>
                  <strong>{stop.name}</strong>
                  <span className="muted">{stopNote(stop, booking)}</span>
                </li>
              ))}
            </ol>
          </section>
        </>
      )}
    </div>
  );
}