// Keep BOOKING_STATUS the same as the CHECK in migrations/501_create_booking_tables.sql.
const BOOKING_STATUS = Object.freeze({
  CONFIRMED: 'CONFIRMED',
  CANCELLED: 'CANCELLED',
});

/** Filter for GET /bookings/mine. */
const BOOKING_WHEN = Object.freeze({ UPCOMING: 'upcoming', PAST: 'past' });

const BOOKING_RULES = Object.freeze({
  MAX_SEATS: 14, // same as TRIP_RULES.MAX_SEATS and the bookings.seats CHECK
  REFERENCE_PREFIX: 'BK-',
  REFERENCE_LENGTH: 6,
  // No 0/O or 1/I, so a reference read out loud or over the phone is not mistaken.
  REFERENCE_ALPHABET: 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789',
});

module.exports = { BOOKING_STATUS, BOOKING_WHEN, BOOKING_RULES };
