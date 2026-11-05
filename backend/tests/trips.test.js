const crypto = require('node:crypto');
const request = require('supertest');
const db = require('../src/db');
const { reserveSeats, releaseSeats } = require('../src/modules/trips');
const { app, post, get, patch, signedInUser } = require('./helpers/api');
const { startTestDb, resetTestDb, stopTestDb } = require('./helpers/test-db');

beforeAll(startTestDb);
beforeEach(resetTestDb);
afterAll(stopTestDb);

const del = (path, token) =>
  request(app).delete(`/api/v1${path}`).set('Authorization', `Bearer ${token}`);

const inHours = (hours) => new Date(Date.now() + hours * 3_600_000).toISOString();
/** Sri Lankan calendar date of a moment, as the search API expects. */
const colomboDate = (iso) => new Date(new Date(iso).getTime() + 5.5 * 3_600_000).toISOString().slice(0, 10);

const STOPS = [
  { name: 'Colombo Fort', lat: 6.9344, lng: 79.8428 },
  { name: 'Kadawatha', lat: 7.001, lng: 79.953 },
  { name: 'Kegalle', lat: 7.2513, lng: 80.3464 },
  { name: 'Kandy', lat: 7.2906, lng: 80.6337 },
];

const tripBody = (overrides = {}) => ({
  vehicleId: crypto.randomUUID(),
  pricingMode: 'FIXED',
  departureAt: inHours(26),
  seatsOffered: 3,
  basePriceCents: 250000,
  stops: STOPS,
  ...overrides,
});

/** Works before and after the drivers module is merged: approves the driver if it exists. */
async function approveDriver(userId) {
  const { rows } = await db.query("SELECT to_regclass('public.driver_profiles') IS NOT NULL AS present");
  if (!rows[0].present) return;
  await db.query(
    `INSERT INTO driver_profiles (user_id, license_number, license_expiry, nic_number, verification_status)
     VALUES ($1, $2, '2030-01-01', $3, 'APPROVED')`,
    [userId, `B${userId.slice(0, 8)}`, `N${userId.slice(0, 11)}`],
  );
}

async function signedInDriver() {
  const { user, tokens } = await signedInUser({ role: 'DRIVER' });
  await approveDriver(user.id);
  return { user, token: tokens.accessToken };
}

async function signedInPassenger() {
  const { user, tokens } = await signedInUser({ role: 'PASSENGER' });
  return { user, token: tokens.accessToken };
}

async function createTrip(token, overrides) {
  const res = await post('/trips', tripBody(overrides), token);
  expect(res.status).toBe(201);
  return res.body.data.trip;
}

async function publishedTrip(token, overrides) {
  const trip = await createTrip(token, overrides);
  const res = await post(`/trips/${trip.id}/publish`, {}, token);
  expect(res.status).toBe(200);
  return res.body.data.trip;
}

describe('POST /trips', () => {
  test('creates a draft with stops, legs and route summary', async () => {
    const { user, token } = await signedInDriver();

    const trip = await createTrip(token);

    expect(trip).toMatchObject({
      driverId: user.id,
      status: 'DRAFT',
      originName: 'Colombo Fort',
      destinationName: 'Kandy',
      seatsOffered: 3,
      seatsAvailable: 3,
    });
    expect(trip.stops).toHaveLength(4);
    expect(trip.legs).toHaveLength(3);
    expect(trip.distanceKm).toBeGreaterThan(90);
    expect(trip.stops[0].plannedAt).not.toBeNull();
  });

  test('requires being signed in', async () => {
    expect((await post('/trips', tripBody())).status).toBe(401);
  });

  test('only drivers can create trips', async () => {
    const { token } = await signedInPassenger();
    expect((await post('/trips', tripBody(), token)).status).toBe(403);
  });

  test.each([
    ['one stop', { stops: [STOPS[0]] }],
    ['unknown field', { colour: 'red' }],
    ['zero seats', { seatsOffered: 0 }],
    ['cargo without capacity', { allowsCargo: true }],
    ['bad vehicle id', { vehicleId: 'abc' }],
  ])('rejects %s', async (_name, overrides) => {
    const { token } = await signedInDriver();
    const res = await post('/trips', tripBody(overrides), token);
    expect(res.status).toBe(422);
    expect(res.body.meta.code).toBe('VALIDATION_ERROR');
  });

  test.each([
    ['departure in 10 minutes', { departureAt: inHours(0.1) }, 'DEPARTURE_TOO_SOON'],
    ['departure in 90 days', { departureAt: inHours(24 * 90) }, 'DEPARTURE_TOO_FAR'],
    ['arrival before departure', { estimatedArrivalAt: inHours(25) }, 'INVALID_ARRIVAL'],
    ['the same stop twice in a row', { stops: [STOPS[0], STOPS[0], STOPS[3]] }, 'INVALID_STOPS'],
  ])('refuses %s', async (_name, overrides, code) => {
    const { token } = await signedInDriver();
    const res = await post('/trips', tripBody(overrides), token);
    expect(res.status).toBe(422);
    expect(res.body.meta.code).toBe(code);
  });
});

describe('GET and PATCH /trips/:id', () => {
  test('a draft is hidden from other users', async () => {
    const { token } = await signedInDriver();
    const trip = await createTrip(token);
    const passenger = await signedInPassenger();

    expect((await get(`/trips/${trip.id}`, passenger.token)).status).toBe(404);
    expect((await get(`/trips/${trip.id}`, token)).status).toBe(200);
  });

  test('another driver cannot edit the trip', async () => {
    const owner = await signedInDriver();
    const other = await signedInDriver();
    const trip = await createTrip(owner.token);

    const res = await patch(`/trips/${trip.id}`, other.token, { notes: 'mine now' });

    expect(res.status).toBe(403);
    expect(res.body.meta.code).toBe('NOT_TRIP_OWNER');
  });

  test('a draft can change its route', async () => {
    const { token } = await signedInDriver();
    const trip = await createTrip(token);

    const res = await patch(`/trips/${trip.id}`, token, { stops: [STOPS[0], STOPS[2]], notes: 'AC car' });

    expect(res.status).toBe(200);
    expect(res.body.data.trip).toMatchObject({ destinationName: 'Kegalle', notes: 'AC car' });
    expect(res.body.data.trip.legs).toHaveLength(1);
  });

  test('a published trip keeps its route and departure', async () => {
    const { token } = await signedInDriver();
    const trip = await publishedTrip(token);

    const locked = await patch(`/trips/${trip.id}`, token, { stops: [STOPS[0], STOPS[2]] });
    expect(locked.status).toBe(409);
    expect(locked.body.meta.code).toBe('TRIP_LOCKED');

    const allowed = await patch(`/trips/${trip.id}`, token, { seatsOffered: 2, basePriceCents: 200000 });
    expect(allowed.status).toBe(200);
    expect(allowed.body.data.trip).toMatchObject({ seatsOffered: 2, seatsAvailable: 2, basePriceCents: 200000 });
  });
});

describe('trip lifecycle', () => {
  test('publish, then cancel with a reason', async () => {
    const { token } = await signedInDriver();
    const trip = await publishedTrip(token);
    expect(trip.status).toBe('SCHEDULED');

    expect((await post(`/trips/${trip.id}/cancel`, {}, token)).status).toBe(422);
    const cancelled = await post(`/trips/${trip.id}/cancel`, { reason: 'Vehicle breakdown' }, token);
    expect(cancelled.status).toBe(200);
    expect(cancelled.body.data.trip).toMatchObject({ status: 'CANCELLED', cancelReason: 'Vehicle breakdown' });

    const again = await post(`/trips/${trip.id}/publish`, {}, token);
    expect(again.status).toBe(409);
    expect(again.body.meta.code).toBe('INVALID_STATUS_CHANGE');
  });

  test('cannot start more than 30 minutes early', async () => {
    const { token } = await signedInDriver();
    const trip = await publishedTrip(token);

    const res = await post(`/trips/${trip.id}/start`, {}, token);

    expect(res.status).toBe(409);
    expect(res.body.meta.code).toBe('TOO_EARLY_TO_START');
  });

  test('start and complete a trip that is about to leave', async () => {
    const { token } = await signedInDriver();
    const trip = await publishedTrip(token);
    // Move the departure to 10 minutes from now, as if the trip were about to leave.
    await db.query("UPDATE trips SET departure_at = now() + interval '10 minutes' WHERE id = $1", [trip.id]);

    const started = await post(`/trips/${trip.id}/start`, {}, token);
    expect(started.status).toBe(200);
    expect(started.body.data.trip.status).toBe('IN_PROGRESS');

    const completed = await post(`/trips/${trip.id}/complete`, {}, token);
    expect(completed.status).toBe(200);
    expect(completed.body.data.trip.status).toBe('COMPLETED');
  });

  test('GET /trips/mine lists only my trips with paging', async () => {
    const me = await signedInDriver();
    const other = await signedInDriver();
    await createTrip(me.token);
    await createTrip(me.token, { departureAt: inHours(50) });
    await createTrip(other.token);

    const res = await get('/trips/mine?limit=1', me.token);

    expect(res.status).toBe(200);
    expect(res.body.data.trips).toHaveLength(1);
    expect(res.body.meta).toMatchObject({ page: 1, limit: 1, total: 2, totalPages: 2 });
    expect(res.body.data.trips[0].originName).toBe('Colombo Fort');
  });
});

describe('search and seats per segment', () => {
  const searchKadawathaToKegalle = (token, seats = 1, departureAt = inHours(26)) =>
    get(
      `/trips/search?fromLat=7.0&fromLng=79.95&toLat=7.25&toLng=80.35&date=${colomboDate(departureAt)}&seats=${seats}`,
      token,
    );

  test('finds a trip for a segment in the middle of its route', async () => {
    const driver = await signedInDriver();
    const trip = await publishedTrip(driver.token);
    await createTrip(driver.token); // drafts are not searchable
    const passenger = await signedInPassenger();

    const res = await searchKadawathaToKegalle(passenger.token, 2);

    expect(res.status).toBe(200);
    expect(res.body.data.results).toHaveLength(1);
    const [hit] = res.body.data.results;
    expect(hit).toMatchObject({ tripId: trip.id, seatsAvailable: 3 });
    expect(hit.pickup).toMatchObject({ stopOrder: 1, name: 'Kadawatha' });
    expect(hit.drop).toMatchObject({ stopOrder: 2, name: 'Kegalle' });
    expect(hit.segmentPriceCents).toBeLessThan(250000);
  });

  test('a seat taken on one part of the route is free on another part', async () => {
    const driver = await signedInDriver();
    const trip = await publishedTrip(driver.token);
    const passenger = await signedInPassenger();

    // Book all 3 seats from Kadawatha (1) to Kandy (3).
    await db.transaction((tx) => reserveSeats(tx, trip.id, 1, 3, 3));

    const full = await get(`/trips/${trip.id}/availability?fromStop=0&toStop=2`, passenger.token);
    expect(full.body.data.availability.seatsAvailable).toBe(0);
    const free = await get(`/trips/${trip.id}/availability?fromStop=0&toStop=1`, passenger.token);
    expect(free.body.data.availability.seatsAvailable).toBe(3);

    expect((await searchKadawathaToKegalle(passenger.token)).body.data.results).toHaveLength(0);
    await expect(db.transaction((tx) => reserveSeats(tx, trip.id, 2, 3, 1))).rejects.toMatchObject({
      status: 409,
      code: 'NOT_ENOUGH_SEATS',
    });

    const detail = await get(`/trips/${trip.id}`, driver.token);
    expect(detail.body.data.trip.seatsAvailable).toBe(0);
    expect((await patch(`/trips/${trip.id}`, driver.token, { seatsOffered: 2 })).status).toBe(409);

    await db.transaction((tx) => releaseSeats(tx, trip.id, 1, 3, 3));
    expect((await get(`/trips/${trip.id}`, driver.token)).body.data.trip.seatsAvailable).toBe(3);
  });

  test('rejects a drop stop before the pickup stop', async () => {
    const driver = await signedInDriver();
    const trip = await publishedTrip(driver.token);

    const res = await get(`/trips/${trip.id}/availability?fromStop=2&toStop=1`, driver.token);

    expect(res.status).toBe(422);
  });
});

describe('/saved-routes', () => {
  test('create, refuse a duplicate name, list and delete', async () => {
    const { token } = await signedInDriver();
    const body = { name: 'Weekly Kandy run', stops: STOPS };

    const created = await post('/saved-routes', body, token);
    expect(created.status).toBe(201);
    const duplicate = await post('/saved-routes', body, token);
    expect(duplicate.status).toBe(409);
    expect(duplicate.body.meta.code).toBe('ROUTE_NAME_TAKEN');

    const list = await get('/saved-routes', token);
    expect(list.body.data.savedRoutes).toHaveLength(1);
    expect(list.body.data.savedRoutes[0].stops).toHaveLength(4);

    const { id } = created.body.data.savedRoute;
    expect((await del(`/saved-routes/${id}`, token)).status).toBe(200);
    expect((await del(`/saved-routes/${id}`, token)).status).toBe(404);
  });

  test('passengers cannot use saved routes', async () => {
    const { token } = await signedInPassenger();
    expect((await get('/saved-routes', token)).status).toBe(403);
  });
});
