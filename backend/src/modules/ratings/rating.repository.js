// All rating SQL. Every function takes an optional `client`, so the service can pass a
// transaction (db.transaction gives one) or use the shared db.
const db = require('../../db');

const RATING_COLUMNS = 'id, trip_id, rater_user_id, ratee_user_id, rater_role, stars, review, created_at';

const TRIP_COLUMNS = `t.origin_name, t.destination_name, t.departure_at, t.completed_at`;

// The rated person's part in the trip is the opposite of the rater's.
const RATEE_ROLE_FILTER = Object.freeze({ DRIVER: 'PASSENGER', PASSENGER: 'DRIVER' });

/** The trip fields the rating rules need. Read-only: the trips module owns this table. */
async function findTrip(tripId, client = db) {
  const { rows } = await client.query('SELECT id, driver_user_id, status FROM trips WHERE id = $1', [tripId]);
  return rows[0] || null;
}

/** True if the user has a CONFIRMED booking on the trip. Read-only: bookings owns that table. */
async function isConfirmedPassenger(tripId, userId, client = db) {
  const { rows } = await client.query(
    `SELECT 1 FROM bookings WHERE trip_id = $1 AND passenger_user_id = $2 AND status = 'CONFIRMED'`,
    [tripId, userId],
  );
  return rows.length > 0;
}

async function userExists(userId, client = db) {
  const { rows } = await client.query('SELECT 1 FROM users WHERE id = $1', [userId]);
  return rows.length > 0;
}

async function insert(rating, client = db) {
  const { rows } = await client.query(
    `INSERT INTO ratings (trip_id, rater_user_id, ratee_user_id, rater_role, stars, review)
     VALUES ($1, $2, $3, $4, $5, $6)
     RETURNING ${RATING_COLUMNS}`,
    [rating.tripId, rating.raterUserId, rating.rateeUserId, rating.raterRole, rating.stars, rating.review],
  );
  return rows[0];
}

/** Average (2 decimals, null when there are none) and count of the ratings a user received. */
async function summaryFor(userId, { role = null } = {}, client = db) {
  const { rows } = await client.query(
    `SELECT round(avg(stars), 2)::float8 AS average_rating, count(*)::int AS rating_count
     FROM ratings WHERE ratee_user_id = $1 AND ($2::text IS NULL OR rater_role = $2::text)`,
    [userId, role ? RATEE_ROLE_FILTER[role] : null],
  );
  return rows[0];
}

/** One page of the ratings a user received, newest first, with the reviewer and trip. */
async function listReceived(userId, { role = null, page, limit }, client = db) {
  const filter = 'r.ratee_user_id = $1 AND ($2::text IS NULL OR r.rater_role = $2::text)';
  const params = [userId, role ? RATEE_ROLE_FILTER[role] : null];
  const count = await client.query(`SELECT count(*)::int AS total FROM ratings r WHERE ${filter}`, params);
  const { rows } = await client.query(
    `SELECT r.id, r.trip_id, r.rater_user_id, r.ratee_user_id, r.rater_role, r.stars, r.review,
            r.created_at, u.full_name AS other_name, ${TRIP_COLUMNS}
     FROM ratings r
     JOIN users u ON u.id = r.rater_user_id
     JOIN trips t ON t.id = r.trip_id
     WHERE ${filter}
     ORDER BY r.created_at DESC, r.id
     LIMIT $3::int OFFSET $4::int`,
    [...params, limit, (page - 1) * limit],
  );
  return { ratings: rows, total: count.rows[0].total };
}

/** One page of the ratings a user gave, newest first, with the person rated and the trip. */
async function listGiven(userId, { page, limit }, client = db) {
  const count = await client.query('SELECT count(*)::int AS total FROM ratings WHERE rater_user_id = $1', [userId]);
  const { rows } = await client.query(
    `SELECT r.id, r.trip_id, r.rater_user_id, r.ratee_user_id, r.rater_role, r.stars, r.review,
            r.created_at, u.full_name AS other_name, ${TRIP_COLUMNS}
     FROM ratings r
     JOIN users u ON u.id = r.ratee_user_id
     JOIN trips t ON t.id = r.trip_id
     WHERE r.rater_user_id = $1
     ORDER BY r.created_at DESC, r.id
     LIMIT $2::int OFFSET $3::int`,
    [userId, limit, (page - 1) * limit],
  );
  return { ratings: rows, total: count.rows[0].total };
}

/**
 * Everyone the user can still rate on COMPLETED trips: the driver of each trip they had a
 * CONFIRMED booking on, and the CONFIRMED passengers of each trip they drove.
 */
async function listPending(userId, client = db) {
  const notRated = `NOT EXISTS (
    SELECT 1 FROM ratings r WHERE r.trip_id = t.id AND r.rater_user_id = $1 AND r.ratee_user_id = x.ratee_id)`;
  const { rows } = await client.query(
    `SELECT x.trip_id, x.ratee_id, x.ratee_role, u.full_name AS other_name, ${TRIP_COLUMNS}
     FROM (
       SELECT b.trip_id, t.driver_user_id AS ratee_id, 'DRIVER' AS ratee_role
       FROM bookings b JOIN trips t ON t.id = b.trip_id
       WHERE b.passenger_user_id = $1 AND b.status = 'CONFIRMED'
       UNION ALL
       SELECT b.trip_id, b.passenger_user_id AS ratee_id, 'PASSENGER' AS ratee_role
       FROM bookings b JOIN trips t ON t.id = b.trip_id
       WHERE t.driver_user_id = $1 AND b.status = 'CONFIRMED'
     ) x
     JOIN trips t ON t.id = x.trip_id
     JOIN users u ON u.id = x.ratee_id
     WHERE t.status = 'COMPLETED' AND x.ratee_id <> $1 AND ${notRated}
     ORDER BY t.completed_at DESC NULLS LAST, t.id, u.full_name, x.ratee_id`,
    [userId],
  );
  return rows;
}

module.exports = {
  findTrip,
  isConfirmedPassenger,
  userExists,
  insert,
  summaryFor,
  listReceived,
  listGiven,
  listPending,
};
