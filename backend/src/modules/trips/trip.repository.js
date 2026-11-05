// All trip SQL. Every function takes an optional `client`, so the service can pass a
// transaction (db.transaction gives one) or use the shared db.
const db = require('../../db');

const TRIP_COLUMNS = `id, driver_user_id, vehicle_id, pricing_mode, status, origin_name, destination_name,
  departure_at, estimated_arrival_at, seats_offered, seats_available, base_price_cents, distance_m,
  duration_s, allows_cargo, cargo_capacity_kg::float8 AS cargo_capacity_kg, notes, cancel_reason,
  published_at, started_at, completed_at, cancelled_at, created_at, updated_at`;

async function insertTrip(trip, client = db) {
  const { rows } = await client.query(
    `INSERT INTO trips (driver_user_id, vehicle_id, pricing_mode, origin_name, destination_name,
       departure_at, estimated_arrival_at, seats_offered, seats_available, base_price_cents,
       distance_m, duration_s, allows_cargo, cargo_capacity_kg, notes)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $8, $9, $10, $11, $12, $13, $14)
     RETURNING ${TRIP_COLUMNS}`,
    [
      trip.driverUserId,
      trip.vehicleId,
      trip.pricingMode,
      trip.originName,
      trip.destinationName,
      trip.departureAt,
      trip.estimatedArrivalAt ?? null,
      trip.seatsOffered,
      trip.basePriceCents,
      trip.distanceM,
      trip.durationS ?? null,
      trip.allowsCargo,
      trip.allowsCargo ? trip.cargoCapacityKg : null,
      trip.notes ?? null,
    ],
  );
  return rows[0];
}

/** Replaces all stops and legs of a trip (only allowed while nobody has a seat). */
async function replaceStops(tripId, stops, client = db) {
  await client.query('DELETE FROM trip_legs WHERE trip_id = $1', [tripId]);
  await client.query('DELETE FROM trip_stops WHERE trip_id = $1', [tripId]);
  for (const [order, stop] of stops.entries()) {
    await client.query(
      `INSERT INTO trip_stops (trip_id, stop_order, name, lat, lng, distance_from_start_m, planned_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [tripId, order, stop.name, stop.lat, stop.lng, stop.distance_from_start_m, stop.plannedAt ?? null],
    );
  }
  await client.query(
    `INSERT INTO trip_legs (trip_id, leg_index)
     SELECT $1, leg FROM generate_series(0, $2::int - 1) AS leg`,
    [tripId, stops.length - 1],
  );
}

async function findById(id, client = db) {
  const { rows } = await client.query(`SELECT ${TRIP_COLUMNS} FROM trips WHERE id = $1`, [id]);
  return rows[0] || null;
}

/** Locks the trip row until the transaction ends. */
async function lock(id, client) {
  const { rows } = await client.query(`SELECT ${TRIP_COLUMNS} FROM trips WHERE id = $1 FOR UPDATE`, [id]);
  return rows[0] || null;
}

async function findStops(tripId, client = db) {
  const { rows } = await client.query(
    `SELECT stop_order, name, lat, lng, distance_from_start_m, planned_at
     FROM trip_stops WHERE trip_id = $1 ORDER BY stop_order`,
    [tripId],
  );
  return rows;
}

/** Array where index = leg_index and value = seats_reserved. */
async function findLegSeats(tripId, client = db) {
  const { rows } = await client.query(
    'SELECT leg_index, seats_reserved FROM trip_legs WHERE trip_id = $1 ORDER BY leg_index',
    [tripId],
  );
  return rows.map((row) => row.seats_reserved);
}

/** Map of trip id -> leg seat array, for many trips at once. */
async function findLegSeatsForTrips(tripIds, client = db) {
  const byTrip = new Map();
  if (tripIds.length === 0) return byTrip;
  const { rows } = await client.query(
    `SELECT trip_id, leg_index, seats_reserved FROM trip_legs
     WHERE trip_id = ANY($1::uuid[]) ORDER BY trip_id, leg_index`,
    // Postgres array literal works the same with pg and with PGlite in tests.
    [`{${tripIds.join(',')}}`],
  );
  for (const row of rows) {
    if (!byTrip.has(row.trip_id)) byTrip.set(row.trip_id, []);
    byTrip.get(row.trip_id)[row.leg_index] = row.seats_reserved;
  }
  return byTrip;
}

const COLUMN_FOR = Object.freeze({
  originName: 'origin_name',
  destinationName: 'destination_name',
  departureAt: 'departure_at',
  estimatedArrivalAt: 'estimated_arrival_at',
  seatsOffered: 'seats_offered',
  seatsAvailable: 'seats_available',
  basePriceCents: 'base_price_cents',
  distanceM: 'distance_m',
  allowsCargo: 'allows_cargo',
  cargoCapacityKg: 'cargo_capacity_kg',
  notes: 'notes',
  status: 'status',
  cancelReason: 'cancel_reason',
  publishedAt: 'published_at',
  startedAt: 'started_at',
  completedAt: 'completed_at',
  cancelledAt: 'cancelled_at',
});

async function update(id, changes, client = db) {
  const sets = [];
  const values = [id];
  for (const [key, value] of Object.entries(changes)) {
    if (value === undefined) continue;
    const column = COLUMN_FOR[key];
    if (!column) throw new Error(`Unknown trip field: ${key}`);
    values.push(value);
    sets.push(`${column} = $${values.length}`);
  }
  if (sets.length === 0) return findById(id, client);
  const { rows } = await client.query(
    `UPDATE trips SET ${sets.join(', ')}, updated_at = now() WHERE id = $1 RETURNING ${TRIP_COLUMNS}`,
    values,
  );
  return rows[0] || null;
}

/** One page of a driver's trips, newest departure first, and the total. */
async function listForDriver(driverUserId, { status = null, page, limit }, client = db) {
  const filter = 'driver_user_id = $1 AND ($2::text IS NULL OR status = $2::text)';
  const count = await client.query(`SELECT count(*)::int AS total FROM trips WHERE ${filter}`, [
    driverUserId,
    status,
  ]);
  const { rows } = await client.query(
    `SELECT ${TRIP_COLUMNS} FROM trips WHERE ${filter}
     ORDER BY departure_at DESC, id LIMIT $3::int OFFSET $4::int`,
    [driverUserId, status, limit, (page - 1) * limit],
  );
  return { trips: rows, total: count.rows[0].total };
}

/**
 * Scheduled (trip, pickup stop, drop stop) pairs where the pickup is inside fromBox, the drop
 * is inside toBox and comes later on the route. The service then checks exact distances.
 */
async function searchCandidates({ fromBox, toBox, dayStart, dayEnd, pricingMode = null }, client = db) {
  const { rows } = await client.query(
    `SELECT t.id AS trip_id, t.driver_user_id, t.vehicle_id, t.pricing_mode, t.departure_at,
            t.seats_offered, t.base_price_cents, t.distance_m, t.allows_cargo,
            o.stop_order AS from_order, o.name AS from_name, o.lat AS from_lat, o.lng AS from_lng,
            o.distance_from_start_m AS from_m, o.planned_at AS from_at,
            d.stop_order AS to_order, d.name AS to_name, d.lat AS to_lat, d.lng AS to_lng,
            d.distance_from_start_m AS to_m, d.planned_at AS to_at
     FROM trips t
     JOIN trip_stops o ON o.trip_id = t.id
     JOIN trip_stops d ON d.trip_id = t.id AND d.stop_order > o.stop_order
     WHERE t.status = 'SCHEDULED'
       AND t.departure_at >= $1::timestamptz AND t.departure_at < $2::timestamptz
       AND t.departure_at > now()
       AND o.lat BETWEEN $3 AND $4 AND o.lng BETWEEN $5 AND $6
       AND d.lat BETWEEN $7 AND $8 AND d.lng BETWEEN $9 AND $10
       AND ($11::text IS NULL OR t.pricing_mode = $11::text)`,
    [
      dayStart,
      dayEnd,
      fromBox.minLat,
      fromBox.maxLat,
      fromBox.minLng,
      fromBox.maxLng,
      toBox.minLat,
      toBox.maxLat,
      toBox.minLng,
      toBox.maxLng,
      pricingMode,
    ],
  );
  return rows;
}

/** Locks the legs of a segment until the transaction ends. */
async function lockLegs(tripId, fromStop, toStop, client) {
  const { rows } = await client.query(
    `SELECT leg_index, seats_reserved FROM trip_legs
     WHERE trip_id = $1 AND leg_index >= $2 AND leg_index < $3
     ORDER BY leg_index FOR UPDATE`,
    [tripId, fromStop, toStop],
  );
  return rows;
}

async function addToLegs(tripId, fromStop, toStop, delta, client) {
  await client.query(
    `UPDATE trip_legs SET seats_reserved = seats_reserved + $4
     WHERE trip_id = $1 AND leg_index >= $2 AND leg_index < $3`,
    [tripId, fromStop, toStop, delta],
  );
}

/** Recalculates trips.seats_available (full route) from the legs. */
async function refreshSeatsAvailable(tripId, client = db) {
  await client.query(
    `UPDATE trips SET seats_available = GREATEST(0, seats_offered - COALESCE(
       (SELECT max(seats_reserved) FROM trip_legs WHERE trip_id = $1), 0)), updated_at = now()
     WHERE id = $1`,
    [tripId],
  );
}

async function maxSeatsReserved(tripId, client = db) {
  const { rows } = await client.query(
    'SELECT COALESCE(max(seats_reserved), 0)::int AS reserved FROM trip_legs WHERE trip_id = $1',
    [tripId],
  );
  return rows[0].reserved;
}

// ---------- saved routes ----------
const SAVED_ROUTE_COLUMNS = 'id, name, stops, created_at';

async function insertSavedRoute(driverUserId, name, stops, client = db) {
  const { rows } = await client.query(
    `INSERT INTO saved_routes (driver_user_id, name, stops) VALUES ($1, $2, $3::jsonb)
     RETURNING ${SAVED_ROUTE_COLUMNS}`,
    [driverUserId, name, JSON.stringify(stops)],
  );
  return rows[0];
}

async function listSavedRoutes(driverUserId, client = db) {
  const { rows } = await client.query(
    `SELECT ${SAVED_ROUTE_COLUMNS} FROM saved_routes WHERE driver_user_id = $1 ORDER BY name`,
    [driverUserId],
  );
  return rows;
}

async function deleteSavedRoute(driverUserId, id, client = db) {
  const { rows } = await client.query(
    'DELETE FROM saved_routes WHERE id = $1 AND driver_user_id = $2 RETURNING id',
    [id, driverUserId],
  );
  return rows.length > 0;
}

module.exports = {
  insertTrip,
  replaceStops,
  findById,
  lock,
  findStops,
  findLegSeats,
  findLegSeatsForTrips,
  update,
  listForDriver,
  searchCandidates,
  lockLegs,
  addToLegs,
  refreshSeatsAvailable,
  maxSeatsReserved,
  insertSavedRoute,
  listSavedRoutes,
  deleteSavedRoute,
};
