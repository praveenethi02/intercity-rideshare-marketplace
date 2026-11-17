// All booking SQL. Every function takes an optional `client`, so the service can pass a
// transaction (db.transaction gives one) or use the shared db.
const db = require('../../db');

const BOOKING_COLUMNS = `id, reference, trip_id, passenger_user_id, from_stop, to_stop, seats,
  price_per_seat_cents, total_cents, status, cancel_reason, created_at, updated_at, cancelled_at`;

// A booking with the trip details a list or detail screen needs.
const BOOKING_WITH_TRIP = `
  SELECT b.id, b.reference, b.trip_id, b.passenger_user_id, b.from_stop, b.to_stop, b.seats,
         b.price_per_seat_cents, b.total_cents, b.status, b.cancel_reason, b.created_at,
         b.updated_at, b.cancelled_at,
         t.driver_user_id, t.pricing_mode, t.status AS trip_status, t.origin_name,
         t.destination_name, t.departure_at, t.estimated_arrival_at,
         p.name AS pickup_name, p.planned_at AS pickup_at,
         d.name AS drop_name, d.planned_at AS drop_at
  FROM bookings b
  JOIN trips t ON t.id = b.trip_id
  LEFT JOIN trip_stops p ON p.trip_id = b.trip_id AND p.stop_order = b.from_stop
  LEFT JOIN trip_stops d ON d.trip_id = b.trip_id AND d.stop_order = b.to_stop`;

/** The trip fields the booking rules need. Read-only: the trips module owns this table. */
async function findTrip(tripId, client = db) {
  const { rows } = await client.query(
    `SELECT id, driver_user_id, pricing_mode, status, departure_at, base_price_cents
     FROM trips WHERE id = $1`,
    [tripId],
  );
  return rows[0] || null;
}

async function findConfirmed(tripId, passengerUserId, client = db) {
  const { rows } = await client.query(
    `SELECT id FROM bookings
     WHERE trip_id = $1 AND passenger_user_id = $2 AND status = 'CONFIRMED'`,
    [tripId, passengerUserId],
  );
  return rows[0] || null;
}

async function referenceExists(reference, client = db) {
  const { rows } = await client.query('SELECT 1 FROM bookings WHERE reference = $1', [reference]);
  return rows.length > 0;
}

async function insert(booking, client = db) {
  const { rows } = await client.query(
    `INSERT INTO bookings (reference, trip_id, passenger_user_id, from_stop, to_stop, seats,
       price_per_seat_cents, total_cents)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
     RETURNING ${BOOKING_COLUMNS}`,
    [
      booking.reference,
      booking.tripId,
      booking.passengerUserId,
      booking.fromStop,
      booking.toStop,
      booking.seats,
      booking.pricePerSeatCents,
      booking.totalCents,
    ],
  );
  return rows[0];
}

async function findById(id, client = db) {
  const { rows } = await client.query(`${BOOKING_WITH_TRIP} WHERE b.id = $1`, [id]);
  return rows[0] || null;
}

/** Locks the booking row until the transaction ends. */
async function lock(id, client) {
  const { rows } = await client.query(`SELECT ${BOOKING_COLUMNS} FROM bookings WHERE id = $1 FOR UPDATE`, [id]);
  return rows[0] || null;
}

// upcoming: confirmed bookings on trips that have not finished (SCHEDULED or IN_PROGRESS).
// past: everything else (completed or cancelled trips, cancelled bookings).
const UPCOMING = "(b.status = 'CONFIRMED' AND t.status IN ('SCHEDULED', 'IN_PROGRESS'))";
const WHEN_FILTER = Object.freeze({ upcoming: UPCOMING, past: `NOT ${UPCOMING}` });

/** One page of a passenger's bookings, newest first, and the total. */
async function listForPassenger(passengerUserId, { when = null, page, limit }, client = db) {
  const filter = `b.passenger_user_id = $1${when ? ` AND ${WHEN_FILTER[when]}` : ''}`;
  const count = await client.query(
    `SELECT count(*)::int AS total FROM bookings b JOIN trips t ON t.id = b.trip_id WHERE ${filter}`,
    [passengerUserId],
  );
  const { rows } = await client.query(
    `${BOOKING_WITH_TRIP} WHERE ${filter}
     ORDER BY b.created_at DESC, b.id LIMIT $2::int OFFSET $3::int`,
    [passengerUserId, limit, (page - 1) * limit],
  );
  return { bookings: rows, total: count.rows[0].total };
}

async function cancel(id, reason, client = db) {
  await client.query(
    `UPDATE bookings SET status = 'CANCELLED', cancel_reason = $2, cancelled_at = now(), updated_at = now()
     WHERE id = $1`,
    [id, reason ?? null],
  );
}

module.exports = {
  findTrip,
  findConfirmed,
  referenceExists,
  insert,
  findById,
  lock,
  listForPassenger,
  cancel,
};
