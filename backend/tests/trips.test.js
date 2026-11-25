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

/** An APPROVED, ACTIVE driver profile. The trip module requires one to create trips. */
async function approveDriver(userId) {
  await db.query(
    `INSERT INTO driver_profiles (user_id, license_number, license_expiry, nic_number, verification_status)
     VALUES ($1, $2, '2030-01-01', $3, 'APPROVED')`,
    [userId, `B${userId.slice(0, 8)}`, `N${userId.slice(0, 11)}`],
  );
}

let plateCounter = 1000;

/**
 * A vehicle in the vehicles table (migration 301), owned by the driver. By default it is an
 * APPROVED, active car with 5 seats in total, 4 of them for passengers, and no cargo space.
 */
async function addVehicle(driverUserId, overrides = {}) {
  const v = {
    vehicleType: 'CAR',
    totalSeats: 5,
    passengerSeats: 4,
    cargoCapacityKg: 0,
    verificationStatus: 'APPROVED',
    isActive: true,
    ...overrides,
  };
  plateCounter += 1;
  const { rows } = await db.query(
    `INSERT INTO vehicles (driver_user_id, vehicle_type, make, model, year, color, plate_number,
       total_seats, passenger_seats, cargo_capacity_kg, verification_status, is_active)
     VALUES ($1, $2, 'Toyota', 'Axio', 2016, 'White', $3, $4, $5, $6, $7, $8)
     RETURNING id`,
    [
      driverUserId,
      v.vehicleType,
      `WP CAB-${plateCounter}`,
      v.totalSeats,
      v.passengerSeats,
      v.cargoCapacityKg,
      v.verificationStatus,
      v.isActive,
    ],
  );
  return rows[0].id;
}

/** The usable vehicle of each signed-in driver, by access token. */
const vehicleOf = new Map();

async function signedInDriver() {
  const { user, tokens } = await signedInUser({ role: 'DRIVER' });
  await approveDriver(user.id);
  const vehicleId = await addVehicle(user.id);
  vehicleOf.set(tokens.accessToken, vehicleId);
  return { user, token: tokens.accessToken, vehicleId };
}

async function signedInPassenger() {
  const { user, tokens } = await signedInUser({ role: 'PASSENGER' });
  return { user, token: tokens.accessToken };
}

const createTripRequest = (token, overrides = {}) =>
  post('/trips', tripBody({ vehicleId: vehicleOf.get(token), ...overrides }), token);

async function createTrip(token, overrides) {
  const res = await createTripRequest(token, overrides);
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
    const res = await createTripRequest(token, overrides);
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
    const res = await createTripRequest(token, overrides);
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

describe('seat and cargo capacity (SCRUM-71, SCRUM-74)', () => {
  const kadawathaToKegalle = (token, departureAt) =>
    get(
      `/trips/search?fromLat=7.0&fromLng=79.95&toLat=7.25&toLng=80.35&date=${colomboDate(departureAt)}`,
      token,
    );

  async function cargoDriver(vehicleCargoKg = 500) {
    const driver = await signedInDriver();
    const vehicleId = await addVehicle(driver.user.id, { cargoCapacityKg: vehicleCargoKg });
    return { ...driver, vehicleId };
  }

  test('search results show seats offered, arrival and cargo capacity as a number', async () => {
    const driver = await cargoDriver();
    const departureAt = inHours(26);
    const cargo = await publishedTrip(driver.token, {
      vehicleId: driver.vehicleId,
      departureAt,
      estimatedArrivalAt: inHours(30),
      allowsCargo: true,
      cargoCapacityKg: 120.5,
    });
    const plain = await publishedTrip(driver.token, { departureAt: inHours(27) });
    const passenger = await signedInPassenger();

    const res = await kadawathaToKegalle(passenger.token, departureAt);
    const byId = Object.fromEntries(res.body.data.results.map((r) => [r.tripId, r]));

    expect(byId[cargo.id]).toMatchObject({
      seatsOffered: 3,
      seatsAvailable: 3,
      allowsCargo: true,
      cargoCapacityKg: 120.5,
    });
    expect(new Date(byId[cargo.id].estimatedArrivalAt).toISOString()).toBe(cargo.estimatedArrivalAt);
    expect(byId[plain.id]).toMatchObject({
      seatsOffered: 3,
      allowsCargo: false,
      cargoCapacityKg: null,
      estimatedArrivalAt: null,
    });
    expect((await get(`/trips/${cargo.id}`, passenger.token)).body.data.trip.cargoCapacityKg).toBe(120.5);
  });

  test('availability lists seats offered, cargo and free seats on each leg of the part', async () => {
    const driver = await cargoDriver();
    const trip = await publishedTrip(driver.token, {
      vehicleId: driver.vehicleId,
      allowsCargo: true,
      cargoCapacityKg: 80,
    });
    const passenger = await signedInPassenger();
    await db.transaction((tx) => reserveSeats(tx, trip.id, 1, 2, 2)); // Kadawatha -> Kegalle

    const res = await get(`/trips/${trip.id}/availability?fromStop=0&toStop=3`, passenger.token);

    expect(res.status).toBe(200);
    expect(res.body.data.availability).toMatchObject({
      seatsOffered: 3,
      seatsAvailable: 1,
      allowsCargo: true,
      cargoCapacityKg: 80,
      legs: [
        { legIndex: 0, fromName: 'Colombo Fort', toName: 'Kadawatha', seatsAvailable: 3 },
        { legIndex: 1, fromName: 'Kadawatha', toName: 'Kegalle', seatsAvailable: 1 },
        { legIndex: 2, fromName: 'Kegalle', toName: 'Kandy', seatsAvailable: 3 },
      ],
    });
    const part = await get(`/trips/${trip.id}/availability?fromStop=2&toStop=3`, passenger.token);
    expect(part.body.data.availability.legs).toEqual([
      { legIndex: 2, fromName: 'Kegalle', toName: 'Kandy', seatsAvailable: 3 },
    ]);
  });

  test('a trip cannot offer more cargo than its vehicle carries', async () => {
    const driver = await cargoDriver(100);

    const cargoTrip = (cargoCapacityKg) =>
      createTripRequest(driver.token, { vehicleId: driver.vehicleId, allowsCargo: true, cargoCapacityKg });

    const over = await cargoTrip(100.5);
    expect(over.status).toBe(422);
    expect(over.body.meta.code).toBe('CARGO_OVER_VEHICLE_LIMIT');

    const full = await cargoTrip(100);
    expect(full.status).toBe(201);
    expect(full.body.data.trip.cargoCapacityKg).toBe(100);
  });

  test('a vehicle without cargo space can only offer trips without cargo', async () => {
    const driver = await signedInDriver(); // default car: 0 kg

    const res = await createTripRequest(driver.token, { allowsCargo: true, cargoCapacityKg: 10 });
    expect(res.status).toBe(422);
    expect(res.body.meta.code).toBe('CARGO_OVER_VEHICLE_LIMIT');
    expect((await createTripRequest(driver.token, { allowsCargo: false })).status).toBe(201);
  });

  test('checks the cargo limit again when the cargo fields change', async () => {
    const driver = await cargoDriver(100);
    const trip = await createTrip(driver.token, { vehicleId: driver.vehicleId }); // a draft, no cargo

    const over = await patch(`/trips/${trip.id}`, driver.token, { allowsCargo: true, cargoCapacityKg: 150 });
    expect(over.status).toBe(422);
    expect(over.body.meta.code).toBe('CARGO_OVER_VEHICLE_LIMIT');

    const ok = await patch(`/trips/${trip.id}`, driver.token, { allowsCargo: true, cargoCapacityKg: 60 });
    expect(ok.status).toBe(200);
    expect(ok.body.data.trip).toMatchObject({ allowsCargo: true, cargoCapacityKg: 60 });
    expect((await patch(`/trips/${trip.id}`, driver.token, { cargoCapacityKg: 101 })).body.meta.code).toBe(
      'CARGO_OVER_VEHICLE_LIMIT',
    );

    // Other edits do not re-check cargo, and turning cargo off is always allowed.
    await db.query('UPDATE vehicles SET cargo_capacity_kg = 0 WHERE id = $1', [driver.vehicleId]);
    expect((await patch(`/trips/${trip.id}`, driver.token, { notes: 'AC van' })).status).toBe(200);
    const off = await patch(`/trips/${trip.id}`, driver.token, { allowsCargo: false });
    expect(off.status).toBe(200);
    expect(off.body.data.trip).toMatchObject({ allowsCargo: false, cargoCapacityKg: null });
  });
});

describe('route-segment matching (SCRUM-72)', () => {
  // Colombo Fort (0) -> Kadawatha (1) -> Kegalle (2) -> Kandy (3)
  const NEAR = {
    fort: { lat: 6.935, lng: 79.843 },
    kadawatha: { lat: 7.0, lng: 79.95 },
    kegalle: { lat: 7.25, lng: 80.35 },
    kandy: { lat: 7.29, lng: 80.63 },
  };
  const DAY = colomboDate(inHours(48));
  const at = (hhmm, day = DAY) => new Date(`${day}T${hhmm}:00+05:30`).toISOString();
  const nextDay = (day) => new Date(new Date(`${day}T00:00:00Z`).getTime() + 86_400_000).toISOString().slice(0, 10);

  const search = (token, from, to, params = {}) =>
    get(
      `/trips/search?${new URLSearchParams({
        fromLat: from.lat,
        fromLng: from.lng,
        toLat: to.lat,
        toLng: to.lng,
        date: DAY,
        ...params,
      })}`,
      token,
    );
  const results = async (...args) => (await search(...args)).body.data.results;

  test('pickup and drop in the middle of the route', async () => {
    const driver = await signedInDriver();
    const trip = await publishedTrip(driver.token, { departureAt: at('08:00') });
    const passenger = await signedInPassenger();

    const [hit, ...rest] = await results(passenger.token, NEAR.kadawatha, NEAR.kegalle);

    expect(rest).toEqual([]);
    expect(hit).toMatchObject({ tripId: trip.id, pickup: { stopOrder: 1 }, drop: { stopOrder: 2 } });
    expect(hit.segmentDistanceKm).toBeLessThan(trip.distanceKm);
  });

  test('the whole route', async () => {
    const driver = await signedInDriver();
    const trip = await publishedTrip(driver.token, { departureAt: at('08:00') });
    const passenger = await signedInPassenger();

    const [hit] = await results(passenger.token, NEAR.fort, NEAR.kandy);

    expect(hit).toMatchObject({ tripId: trip.id, pickup: { stopOrder: 0 }, drop: { stopOrder: 3 } });
    expect(hit.segmentPriceCents).toBe(250000);
    expect(hit.segmentDistanceKm).toBe(trip.distanceKm);
  });

  test('a passenger going the other way is not matched', async () => {
    const driver = await signedInDriver();
    await publishedTrip(driver.token, { departureAt: at('08:00') });
    const passenger = await signedInPassenger();

    expect(await results(passenger.token, NEAR.kegalle, NEAR.kadawatha)).toEqual([]);
    expect(await results(passenger.token, NEAR.kandy, NEAR.fort)).toEqual([]);
  });

  test('stops outside the radius are not matched', async () => {
    const driver = await signedInDriver();
    const trip = await publishedTrip(driver.token, { departureAt: at('08:00') });
    const passenger = await signedInPassenger();
    const gampaha = { lat: 7.0917, lng: 79.9997 }; // about 11 km from Kadawatha

    expect(await results(passenger.token, gampaha, NEAR.kegalle)).toEqual([]);
    expect(await results(passenger.token, gampaha, NEAR.kegalle, { radiusKm: 5 })).toEqual([]);
    const wide = await results(passenger.token, gampaha, NEAR.kegalle, { radiusKm: 15 });
    expect(wide.map((r) => r.tripId)).toEqual([trip.id]);
    expect(wide[0].pickup.distanceFromYouKm).toBeGreaterThan(5);
  });

  test('two nearby stops: the closest pair is used, one result per trip', async () => {
    const driver = await signedInDriver();
    const stops = [
      STOPS[0],
      STOPS[1], // Kadawatha
      { name: 'Kadawatha North', lat: 7.02, lng: 79.965 }, // about 2.5 km further on
      STOPS[2],
      STOPS[3],
    ];
    const trip = await publishedTrip(driver.token, { departureAt: at('08:00'), stops });
    const passenger = await signedInPassenger();

    // Standing next to Kadawatha North; Kadawatha is also inside the 5 km radius.
    const hits = await results(passenger.token, { lat: 7.019, lng: 79.964 }, NEAR.kegalle);

    expect(hits).toHaveLength(1);
    expect(hits[0]).toMatchObject({ tripId: trip.id, pickup: { stopOrder: 2, name: 'Kadawatha North' } });
    expect(hits[0].pickup.distanceFromYouKm).toBeLessThan(0.5);
  });

  test('a full leg outside the segment does not block it, a full leg inside does', async () => {
    const driver = await signedInDriver();
    const trip = await publishedTrip(driver.token, { departureAt: at('08:00') }); // 3 seats
    const passenger = await signedInPassenger();

    // Colombo -> Kadawatha (leg 0) and Kegalle -> Kandy (leg 2) are full.
    await db.transaction((tx) => reserveSeats(tx, trip.id, 0, 1, 3));
    await db.transaction((tx) => reserveSeats(tx, trip.id, 2, 3, 3));

    const middle = await results(passenger.token, NEAR.kadawatha, NEAR.kegalle, { seats: 3 });
    expect(middle).toMatchObject([{ tripId: trip.id, seatsAvailable: 3 }]);
    expect(await results(passenger.token, NEAR.kadawatha, NEAR.kandy)).toEqual([]);
    expect(await results(passenger.token, NEAR.fort, NEAR.kegalle)).toEqual([]);
  });

  test('only SCHEDULED trips that have not left are matched', async () => {
    const driver = await signedInDriver();
    const passenger = await signedInPassenger();
    const today = colomboDate(inHours(1));
    const soon = (minutes) => `now() + interval '${minutes} minutes'`;

    await createTrip(driver.token, { departureAt: at('08:00') }); // DRAFT
    const cancelled = await publishedTrip(driver.token, { departureAt: at('09:00') });
    await post(`/trips/${cancelled.id}/cancel`, { reason: 'Car broke down' }, driver.token);
    expect(await results(passenger.token, NEAR.kadawatha, NEAR.kegalle)).toEqual([]);

    // Trips leaving within the hour: one has left, one is driving, one is done, one is still open.
    const departed = await publishedTrip(driver.token);
    const driving = await publishedTrip(driver.token);
    const done = await publishedTrip(driver.token);
    const open = await publishedTrip(driver.token);
    await db.query(`UPDATE trips SET departure_at = now() - interval '5 minutes' WHERE id = $1`, [departed.id]);
    for (const trip of [driving, done, open]) {
      await db.query(`UPDATE trips SET departure_at = ${soon(20)} WHERE id = $1`, [trip.id]);
    }
    expect((await post(`/trips/${driving.id}/start`, {}, driver.token)).status).toBe(200);
    expect((await post(`/trips/${done.id}/start`, {}, driver.token)).status).toBe(200);
    expect((await post(`/trips/${done.id}/complete`, {}, driver.token)).status).toBe(200);

    // The 20-minute trips may fall on tomorrow's date late at night, so search both days.
    const found = [
      ...(await results(passenger.token, NEAR.kadawatha, NEAR.kegalle, { date: today })),
      ...(await results(passenger.token, NEAR.kadawatha, NEAR.kegalle, { date: nextDay(today) })),
    ].map((r) => r.tripId);
    expect(found).toEqual([open.id]);
  });

  test('a trip near midnight is found on its Sri Lankan date', async () => {
    const driver = await signedInDriver();
    const lateNight = await publishedTrip(driver.token, { departureAt: at('23:50') });
    const afterMidnight = await publishedTrip(driver.token, { departureAt: at('00:10', nextDay(DAY)) });
    const passenger = await signedInPassenger();
    const ids = async (date) => (await results(passenger.token, NEAR.fort, NEAR.kandy, { date })).map((r) => r.tripId);

    // 23:50 in Colombo is 18:20 UTC on the same date; 00:10 is 18:40 UTC on the date before.
    expect(await ids(DAY)).toEqual([lateNight.id]);
    expect(await ids(nextDay(DAY))).toEqual([afterMidnight.id]);
  });
});

describe('search filters and sorting (SCRUM-67, SCRUM-69)', () => {
  // A Sri Lankan day two days from now, so every time on it is far enough ahead to publish.
  const DAY = colomboDate(inHours(48));
  /** An ISO moment at a Sri Lankan clock time on DAY. */
  const at = (hhmm, day = DAY) => new Date(`${day}T${hhmm}:00+05:30`).toISOString();
  const FULL_ROUTE = { fromLat: 6.9344, fromLng: 79.8428, toLat: 7.2906, toLng: 80.6337 };

  /** GET /trips/search from Colombo Fort to Kandy on DAY, with extra query params. */
  const search = (token, params = {}) =>
    get(`/trips/search?${new URLSearchParams({ ...FULL_ROUTE, date: DAY, ...params })}`, token);
  const tripIds = (res) => res.body.data.results.map((r) => r.tripId);

  test("leaves out the signed-in user's own trips", async () => {
    const me = await signedInDriver();
    const other = await signedInDriver();
    const mine = await publishedTrip(me.token, { departureAt: at('08:00') });
    const theirs = await publishedTrip(other.token, { departureAt: at('09:00') });

    const res = await search(me.token);

    expect(res.status).toBe(200);
    expect(tripIds(res)).toEqual([theirs.id]);
    expect(res.body.meta.total).toBe(1);
    expect(tripIds(await search(other.token))).toEqual([mine.id]);
  });

  test('maxPriceCents compares the segment seat price, inclusive', async () => {
    const driver = await signedInDriver();
    const cheap = await publishedTrip(driver.token, { departureAt: at('08:00'), basePriceCents: 150000 });
    await publishedTrip(driver.token, { departureAt: at('09:00'), basePriceCents: 250000 });
    const passenger = await signedInPassenger();

    expect(tripIds(await search(passenger.token, { maxPriceCents: 150000 }))).toEqual([cheap.id]);
    expect(tripIds(await search(passenger.token, { maxPriceCents: 149999 }))).toEqual([]);
    expect(await search(passenger.token, { maxPriceCents: 300000 })).toHaveProperty('body.meta.total', 2);

    // Kadawatha -> Kegalle is a part of the route, so its seat price is lower than the full fare.
    const part = await search(passenger.token, {
      fromLat: 7.0,
      fromLng: 79.95,
      toLat: 7.25,
      toLng: 80.35,
      maxPriceCents: 150000,
    });
    expect(part.body.data.results).toHaveLength(2);
    expect(part.body.data.results.every((r) => r.segmentPriceCents <= 150000)).toBe(true);
  });

  test('departAfter and departBefore use the Sri Lankan pickup time, inclusive', async () => {
    const driver = await signedInDriver();
    const six = await publishedTrip(driver.token, { departureAt: at('06:00') });
    const nine = await publishedTrip(driver.token, { departureAt: at('09:00') });
    const evening = await publishedTrip(driver.token, { departureAt: at('18:30') });
    const passenger = await signedInPassenger();

    const morning = await search(passenger.token, { departAfter: '06:00', departBefore: '09:00' });
    expect(tripIds(morning)).toEqual([six.id, nine.id]);
    expect(morning.body.meta.total).toBe(2);
    expect(tripIds(await search(passenger.token, { departAfter: '09:01' }))).toEqual([evening.id]);
    expect(tripIds(await search(passenger.token, { departBefore: '05:59' }))).toEqual([]);
  });

  test("uses the pickup stop's planned time, not the trip's departure", async () => {
    const driver = await signedInDriver();
    // Leaves Colombo at 05:00 and reaches Kadawatha at 07:30.
    const stops = [STOPS[0], { ...STOPS[1], plannedAt: at('07:30') }, STOPS[2], STOPS[3]];
    const trip = await publishedTrip(driver.token, { departureAt: at('05:00'), stops });
    const passenger = await signedInPassenger();
    const kadawathaToKegalle = { fromLat: 7.0, fromLng: 79.95, toLat: 7.25, toLng: 80.35 };

    expect(tripIds(await search(passenger.token, { ...kadawathaToKegalle, departAfter: '07:30' }))).toEqual([trip.id]);
    expect(tripIds(await search(passenger.token, { ...kadawathaToKegalle, departBefore: '07:29' }))).toEqual([]);
    // From Colombo the pickup time is the departure.
    expect(tripIds(await search(passenger.token, { departBefore: '05:00' }))).toEqual([trip.id]);
  });

  test('cargo filters keep trips that take parcels with enough capacity', async () => {
    const { user, token } = await signedInDriver();
    const vanId = await addVehicle(user.id, { cargoCapacityKg: 500 });
    const cargo = await publishedTrip(token, {
      vehicleId: vanId,
      departureAt: at('08:00'),
      allowsCargo: true,
      cargoCapacityKg: 100,
    });
    await publishedTrip(token, { departureAt: at('09:00') });
    const passenger = await signedInPassenger();

    expect(tripIds(await search(passenger.token, { allowsCargo: 'true' }))).toEqual([cargo.id]);
    expect(tripIds(await search(passenger.token, { minCargoKg: 100 }))).toEqual([cargo.id]);
    expect(tripIds(await search(passenger.token, { minCargoKg: 100.5 }))).toEqual([]);
  });

  test.each([
    ['departAfter equal to departBefore', { departAfter: '10:00', departBefore: '10:00' }],
    ['departAfter after departBefore', { departAfter: '18:00', departBefore: '07:00' }],
    ['a time that does not exist', { departAfter: '24:00' }],
    ['a time without minutes', { departBefore: '9' }],
    ['allowsCargo=false', { allowsCargo: 'false' }],
    ['allowsCargo=1', { allowsCargo: '1' }],
    ['minCargoKg=0', { minCargoKg: 0 }],
    ['a negative maxPriceCents', { maxPriceCents: -1 }],
    ['a fractional maxPriceCents', { maxPriceCents: 10.5 }],
    ['an unknown sort', { sort: 'random' }],
    ['an unknown parameter', { colour: 'red' }],
  ])('rejects %s', async (_name, params) => {
    const passenger = await signedInPassenger();
    const res = await search(passenger.token, params);
    expect(res.status).toBe(422);
    expect(res.body.meta.code).toBe('VALIDATION_ERROR');
  });

  test('sorts by pickup time, price or walking distance, ties by trip id', async () => {
    const driver = await signedInDriver();
    const early = await publishedTrip(driver.token, { departureAt: at('06:00'), basePriceCents: 300000 });
    const late = await publishedTrip(driver.token, { departureAt: at('20:00'), basePriceCents: 100000 });
    // Starts 3 km from the passenger instead of at the Fort.
    const farStops = [{ name: 'Maradana', lat: 6.9289, lng: 79.8656 }, ...STOPS.slice(1)];
    const far = await publishedTrip(driver.token, {
      departureAt: at('12:00'),
      basePriceCents: 200000,
      stops: farStops,
    });
    const passenger = await signedInPassenger();

    expect(tripIds(await search(passenger.token))).toEqual([early.id, far.id, late.id]); // earliest is the default
    expect(tripIds(await search(passenger.token, { sort: 'earliest' }))).toEqual([early.id, far.id, late.id]);
    expect(tripIds(await search(passenger.token, { sort: 'cheapest' }))).toEqual([late.id, far.id, early.id]);
    const closest = tripIds(await search(passenger.token, { sort: 'closest' }));
    expect(closest.at(-1)).toBe(far.id);
    expect(closest.slice(0, 2)).toEqual([early.id, late.id].sort()); // same distance: by trip id
  });

  test('filters and sorts before paging, so pages and totals agree', async () => {
    const driver = await signedInDriver();
    const prices = [100000, 400000, 200000, 500000, 300000];
    for (const [i, basePriceCents] of prices.entries()) {
      await publishedTrip(driver.token, { departureAt: at(`0${i + 5}:00`), basePriceCents });
    }
    const passenger = await signedInPassenger();
    const params = { sort: 'cheapest', maxPriceCents: 400000, limit: 2 };

    const page1 = await search(passenger.token, params);
    const page2 = await search(passenger.token, { ...params, page: 2 });
    const page3 = await search(passenger.token, { ...params, page: 3 });

    expect(page1.body.meta).toMatchObject({ page: 1, limit: 2, total: 4, totalPages: 2 });
    const pricesInOrder = [...page1.body.data.results, ...page2.body.data.results].map((r) => r.segmentPriceCents);
    expect(pricesInOrder).toEqual([100000, 200000, 300000, 400000]);
    expect(page3.body.data.results).toEqual([]);
    expect(page3.body.meta.total).toBe(4);
  });
});

describe('driver and vehicle checks', () => {
  const expectRefused = (res, status, code) => {
    expect(res.status).toBe(status);
    expect(res.body.meta.code).toBe(code);
  };

  test("refuses another driver's vehicle", async () => {
    const me = await signedInDriver();
    const other = await signedInDriver();

    const res = await createTripRequest(me.token, { vehicleId: other.vehicleId });

    expectRefused(res, 403, 'VEHICLE_NOT_OWNED');
  });

  test('refuses a vehicle that does not exist', async () => {
    const { token } = await signedInDriver();

    const res = await createTripRequest(token, { vehicleId: crypto.randomUUID() });

    expectRefused(res, 403, 'VEHICLE_NOT_OWNED');
  });

  test.each(['NOT_SUBMITTED', 'PENDING', 'REJECTED'])('refuses a %s vehicle', async (status) => {
    const { user, token } = await signedInDriver();
    const vehicleId = await addVehicle(user.id, { verificationStatus: status });

    const res = await createTripRequest(token, { vehicleId });

    expectRefused(res, 403, 'VEHICLE_NOT_APPROVED');
  });

  test('refuses an approved vehicle that is inactive', async () => {
    const { user, token } = await signedInDriver();
    const vehicleId = await addVehicle(user.id, { isActive: false });

    const res = await createTripRequest(token, { vehicleId });

    expectRefused(res, 403, 'VEHICLE_INACTIVE');
  });

  test("offers at most the vehicle's passenger seats, never the driver's seat", async () => {
    const { user, token } = await signedInDriver();
    // A van with 8 seats in total, 7 for passengers.
    const vehicleId = await addVehicle(user.id, { vehicleType: 'VAN', totalSeats: 8, passengerSeats: 7 });

    expectRefused(await createTripRequest(token, { vehicleId, seatsOffered: 8 }), 422, 'TOO_MANY_SEATS');

    const allSeats = await createTripRequest(token, { vehicleId, seatsOffered: 7 });
    expect(allSeats.status).toBe(201);
    expect(allSeats.body.data.trip).toMatchObject({ vehicleId, seatsOffered: 7, seatsAvailable: 7 });
  });

  test('checks the seat limit again when a trip is edited', async () => {
    const { token } = await signedInDriver(); // default car: 4 passenger seats
    const trip = await publishedTrip(token);

    expectRefused(await patch(`/trips/${trip.id}`, token, { seatsOffered: 5 }), 422, 'TOO_MANY_SEATS');
    expect((await patch(`/trips/${trip.id}`, token, { seatsOffered: 4 })).status).toBe(200);
  });

  test('refuses a driver whose profile is not approved', async () => {
    const { user, tokens } = await signedInUser({ role: 'DRIVER' });
    const vehicleId = await addVehicle(user.id);

    const res = await post('/trips', tripBody({ vehicleId }), tokens.accessToken);

    expectRefused(res, 403, 'DRIVER_NOT_VERIFIED');
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
