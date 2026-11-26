import { BOOKING_STATUS_LABELS, TRIP_STATUS_LABELS } from './bookingsApi';

/** One badge per booking: a cancelled booking shows Cancelled, otherwise the trip's progress. */
export default function BookingStatusBadge({ booking }) {
  if (booking.status === 'CANCELLED') {
    return <span className="bk-badge bk-badge-cancelled">{BOOKING_STATUS_LABELS.CANCELLED}</span>;
  }
  const tripStatus = booking.trip.status;
  const label = tripStatus === 'SCHEDULED' ? BOOKING_STATUS_LABELS.CONFIRMED : TRIP_STATUS_LABELS[tripStatus];
  return <span className={`bk-badge bk-badge-${tripStatus.toLowerCase()}`}>{label ?? tripStatus}</span>;
}