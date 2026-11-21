const crypto = require('node:crypto');
const db = require('../src/db');
const { post, get, signedInUser } = require('./helpers/api');
const { startTestDb, resetTestDb, stopTestDb } = require('./helpers/test-db');

beforeAll(startTestDb);
beforeEach(resetTestDb);
afterAll(stopTestDb);

const inHours = (hours) => new Date(Date.now() + hours * 3_600_000).toISOString();

const STOPS = [
  { name: 'Colombo Fort', lat: 6.9344, lng: 79.8428 },
  { name: 'Kadawatha', lat: 7.001, lng: 79.953 },
  { name: 'Kegalle', lat: 7.2513, lng: 80.3464 },
  { name: 'Kandy', lat: 7.2906, lng: 80.6337 },
];

// ---------- set-up helpers (same data as bookings.test.js) ----------

async function approveDriver(userId) {
  await db.query(
    `INSERT INTO driver_profiles (user_id, license_number, license_expiry, nic_number, verification_status)
     VALUES ($1, $2, '2030-01-01', $3, 'APPROVED')`,
    [userId, `B${userId.slice(0, 8)}`, `N${userId.slice(0, 11)}`],
  );
}

let plateCounter = 6000;

async function addVehicle(driverUserId) {
  plateCounter += 1;
  const { rows } = await db.query(
    `INSERT INTO vehicles (driver_user_id, vehicle_type, make, model, year, color, plate_number,
       total_seats, passenger_seats, verification_status, is_active)
     VALUES ($1, 'CAR', 'Toyota', 'Axio', 2016, 'White', $2, 5, 4, 'APPROVED', TRUE)
     RETURNING id`,
    [driverUserId, `WP CAR-${plateCounter}`],
  );
  return rows[0].id;
}

async function signedInDriver(names = { firstName: 'Kamal', lastName: 'Perera' }) {
  const { user, tokens } = await signedInUser({ role: 'DRIVER', ...names });
  await approveDriver(user.id);
  const vehicleId = await addVehicle(user.id);
  return { user, token: tokens.accessToken, vehicleId };
}

async function signedInPassenger(names = { firstName: 'Nimal', lastName: 'Silva' }) {
  const { user, tokens } = await signedInUser({ role: 'PASSENGER', ...names });
  return { user, token: tokens.accessToken };
}

/** A published FIXED trip of `driver`, with a CONFIRMED booking for each passenger. */
async function tripWith(driver, passengers) {
  const created = await post(
    '/trips',
    {
      vehicleId: driver.vehicleId,
      pricingMode: 'FIXED',
      departureAt: inHours(26),
      seatsOffered: 3,
      basePriceCents: 250000,
      stops: STOPS,
    },
    driver.token,
  );
  expect(created.status).toBe(201);
  const tripId = created.body.data.trip.id;
  expect((await post(`/trips/${tripId}/publish`, {}, driver.token)).status).toBe(200);
  for (const passenger of passengers) {
    const booked = await post('/bookings', { tripId, fromStop: 0, toStop: 3, seats: 1 }, passenger.token);
    expect(booked.status).toBe(201);
  }
  return tripId;
}

const complete = (tripId) =>
  db.query("UPDATE trips SET status = 'COMPLETED', started_at = now(), completed_at = now() WHERE id = $1", [tripId]);

/** A COMPLETED trip of `driver` that each passenger had a CONFIRMED booking on. */
async function completedTrip(driver, passengers) {
  const tripId = await tripWith(driver, passengers);
  await complete(tripId);
  return tripId;
}

const rate = (token, body) => post('/ratings', { stars: 5, ...body }, token);

async function rated(token, body) {
  const res = await rate(token, body);
  expect(res.status).toBe(201);
  return res.body.data.rating;
}

const driverAverage = async (driverId) => {
  const { rows } = await db.query(
    'SELECT rating_avg::float8 AS avg, rating_count FROM driver_profiles WHERE user_id = $1',
    [driverId],
  );
  return rows[0];
};

const expectError = (res, status, code) => {
  expect(res.status).toBe(status);
  expect(res.body.meta.code).toBe(code);
};

// ---------- tests ----------

describe('POST /ratings', () => {
  test('a passenger rates the driver and the driver average updates', async () => {
    const driver = await signedInDriver();
    const first = await signedInPassenger();
    const second = await signedInPassenger({ firstName: 'Sunil', lastName: 'Fernando' });
    const tripId = await completedTrip(driver, [first, second]);

    const rating = await rated(first.token, { tripId, rateeId: driver.user.id, stars: 4, review: '  Safe driver  ' });

    expect(rating).toMatchObject({
      tripId,
      raterId: first.user.id,
      rateeId: driver.user.id,
      raterRole: 'PASSENGER',
      stars: 4,
      review: 'Safe driver',
    });
    expect(rating.id).toEqual(expect.any(String));
    expect(await driverAverage(driver.user.id)).toEqual({ avg: 4, rating_count: 1 });

    await rated(second.token, { tripId, rateeId: driver.user.id, stars: 5 });
    expect(await driverAverage(driver.user.id)).toEqual({ avg: 4.5, rating_count: 2 });

    // The public driver profile shows the same numbers.
    const profile = await get(`/drivers/${driver.user.id}`, first.token);
    expect(profile.body.data.driver).toMatchObject({ averageRating: 4.5, ratingCount: 2 });
  });

  test('the driver rates a passenger without touching the driver average', async () => {
    const driver = await signedInDriver();
    const passenger = await signedInPassenger();
    const tripId = await completedTrip(driver, [passenger]);

    const rating = await rated(driver.token, { tripId, rateeId: passenger.user.id, stars: 3 });

    expect(rating).toMatchObject({ raterId: driver.user.id, rateeId: passenger.user.id, raterRole: 'DRIVER', stars: 3 });
    expect(await driverAverage(driver.user.id)).toEqual({ avg: 0, rating_count: 0 });
  });

  test('only after the trip is COMPLETED', async () => {
    const driver = await signedInDriver();
    const passenger = await signedInPassenger();
    const tripId = await tripWith(driver, [passenger]);

    expectError(await rate(passenger.token, { tripId, rateeId: driver.user.id }), 409, 'TRIP_NOT_COMPLETED');
    expectError(await rate(driver.token, { tripId, rateeId: passenger.user.id }), 409, 'TRIP_NOT_COMPLETED');

    await db.query("UPDATE trips SET status = 'IN_PROGRESS', started_at = now() WHERE id = $1", [tripId]);
    expectError(await rate(passenger.token, { tripId, rateeId: driver.user.id }), 409, 'TRIP_NOT_COMPLETED');
  });

  test('people who were not on the trip cannot rate, and get 404', async () => {
    const driver = await signedInDriver();
    const passenger = await signedInPassenger();
    const outsider = await signedInPassenger({ firstName: 'Outside', lastName: 'User' });
    const tripId = await completedTrip(driver, [passenger]);

    expectError(await rate(outsider.token, { tripId, rateeId: driver.user.id }), 404, 'TRIP_NOT_FOUND');
    expectError(
      await rate(passenger.token, { tripId: crypto.randomUUID(), rateeId: driver.user.id }),
      404,
      'TRIP_NOT_FOUND',
    );
  });

  test('a cancelled booking does not count as being on the trip', async () => {
    const driver = await signedInDriver();
    const passenger = await signedInPassenger();
    const tripId = await tripWith(driver, [passenger]);
    const [booking] = (await get('/bookings/mine', passenger.token)).body.data.bookings;
    expect((await post(`/bookings/${booking.id}/cancel`, {}, passenger.token)).status).toBe(200);
    await complete(tripId);

    expectError(await rate(passenger.token, { tripId, rateeId: driver.user.id }), 404, 'TRIP_NOT_FOUND');
    expectError(await rate(driver.token, { tripId, rateeId: passenger.user.id }), 422, 'RATEE_NOT_ON_TRIP');
  });

  test('nobody outside the trip can be rated, and passengers cannot rate each other', async () => {
    const driver = await signedInDriver();
    const first = await signedInPassenger();
    const second = await signedInPassenger({ firstName: 'Sunil', lastName: 'Fernando' });
    const outsider = await signedInPassenger({ firstName: 'Outside', lastName: 'User' });
    const tripId = await completedTrip(driver, [first, second]);

    expectError(await rate(driver.token, { tripId, rateeId: outsider.user.id }), 422, 'RATEE_NOT_ON_TRIP');
    expectError(await rate(first.token, { tripId, rateeId: second.user.id }), 422, 'RATEE_NOT_ON_TRIP');
    expectError(await rate(first.token, { tripId, rateeId: outsider.user.id }), 422, 'RATEE_NOT_ON_TRIP');
  });

  test('nobody can rate themselves', async () => {
    const driver = await signedInDriver();
    const passenger = await signedInPassenger();
    const tripId = await completedTrip(driver, [passenger]);

    expectError(await rate(driver.token, { tripId, rateeId: driver.user.id }), 422, 'CANNOT_RATE_SELF');
    expectError(await rate(passenger.token, { tripId, rateeId: passenger.user.id }), 422, 'CANNOT_RATE_SELF');
  });

  test('a second rating of the same person on the same trip returns 409', async () => {
    const driver = await signedInDriver();
    const passenger = await signedInPassenger();
    const tripId = await completedTrip(driver, [passenger]);

    await rated(passenger.token, { tripId, rateeId: driver.user.id, stars: 2 });
    expectError(await rate(passenger.token, { tripId, rateeId: driver.user.id, stars: 5 }), 409, 'ALREADY_RATED');
    await rated(driver.token, { tripId, rateeId: passenger.user.id });
    expectError(await rate(driver.token, { tripId, rateeId: passenger.user.id }), 409, 'ALREADY_RATED');

    // The refused rating did not change the average.
    expect(await driverAverage(driver.user.id)).toEqual({ avg: 2, rating_count: 1 });
  });

  test('the same person can be rated again on another trip', async () => {
    const driver = await signedInDriver();
    const passenger = await signedInPassenger();
    const firstTrip = await completedTrip(driver, [passenger]);
    const secondTrip = await completedTrip(driver, [passenger]);

    await rated(passenger.token, { tripId: firstTrip, rateeId: driver.user.id, stars: 3 });
    await rated(passenger.token, { tripId: secondTrip, rateeId: driver.user.id, stars: 5 });
    expect(await driverAverage(driver.user.id)).toEqual({ avg: 4, rating_count: 2 });
  });

  test('stars must be a whole number from 1 to 5', async () => {
    const driver = await signedInDriver();
    const passenger = await signedInPassenger();
    const tripId = await completedTrip(driver, [passenger]);
    const body = { tripId, rateeId: driver.user.id };

    for (const stars of [0, 6, 4.5, '5', null]) {
      const res = await rate(passenger.token, { ...body, stars });
      expectError(res, 422, 'VALIDATION_ERROR');
      expect(res.body.meta.details[0].field).toBe('body.stars');
    }
    const missing = await post('/ratings', body, passenger.token);
    expectError(missing, 422, 'VALIDATION_ERROR');

    await rated(passenger.token, { ...body, stars: 1 });
  });

  test('a review is optional, trimmed and at most 500 characters', async () => {
    const driver = await signedInDriver();
    const first = await signedInPassenger();
    const second = await signedInPassenger({ firstName: 'Sunil', lastName: 'Fernando' });
    const third = await signedInPassenger({ firstName: 'Ruwan', lastName: 'Jayasuriya' });
    const tripId = await completedTrip(driver, [first, second, third]);
    const body = { tripId, rateeId: driver.user.id };

    const tooLong = await rate(first.token, { ...body, review: 'x'.repeat(501) });
    expectError(tooLong, 422, 'VALIDATION_ERROR');
    expect(tooLong.body.meta.details[0].field).toBe('body.review');

    const longest = await rated(first.token, { ...body, review: ` ${'x'.repeat(500)} ` });
    expect(longest.review).toHaveLength(500);
    expect((await rated(second.token, { ...body, review: '   ' })).review).toBeNull();
    expect((await rated(third.token, body)).review).toBeNull();
  });

  test('extra fields such as raterRole are refused', async () => {
    const driver = await signedInDriver();
    const passenger = await signedInPassenger();
    const tripId = await completedTrip(driver, [passenger]);

    const res = await rate(passenger.token, { tripId, rateeId: driver.user.id, raterRole: 'DRIVER' });
    expectError(res, 422, 'VALIDATION_ERROR');
  });
});

describe('GET /ratings/pending', () => {
  test('lists who each side can still rate and shrinks after rating', async () => {
    const driver = await signedInDriver();
    const first = await signedInPassenger();
    const second = await signedInPassenger({ firstName: 'Sunil', lastName: 'Fernando' });
    const tripId = await completedTrip(driver, [first, second]);
    // A trip that is not completed adds nothing.
    await tripWith(driver, [first]);

    const pending = async (token) => (await get('/ratings/pending', token)).body.data.pending;

    const forPassenger = await pending(first.token);
    expect(forPassenger).toEqual([
      {
        trip: expect.objectContaining({ id: tripId, originName: 'Colombo Fort', destinationName: 'Kandy' }),
        ratee: { id: driver.user.id, name: 'Kamal P.', role: 'DRIVER' },
      },
    ]);
    expect(forPassenger[0].trip.completedAt).toEqual(expect.any(String));

    const forDriver = await pending(driver.token);
    expect(forDriver.map((item) => item.ratee)).toEqual(
      expect.arrayContaining([
        { id: first.user.id, name: 'Nimal S.', role: 'PASSENGER' },
        { id: second.user.id, name: 'Sunil F.', role: 'PASSENGER' },
      ]),
    );
    expect(forDriver).toHaveLength(2);

    await rated(first.token, { tripId, rateeId: driver.user.id });
    await rated(driver.token, { tripId, rateeId: first.user.id });

    expect(await pending(first.token)).toEqual([]);
    expect((await pending(driver.token)).map((item) => item.ratee.id)).toEqual([second.user.id]);
    expect(await pending(second.token)).toHaveLength(1);
  });
});

describe('GET /ratings/users/:userId', () => {
  test('shows received ratings newest first with the right average and count', async () => {
    const driver = await signedInDriver();
    const first = await signedInPassenger();
    const second = await signedInPassenger({ firstName: 'Sunil', lastName: 'Fernando' });
    const third = await signedInPassenger({ firstName: 'Madonna', lastName: 'Ciccone' });
    // Users from before first and last names were split can have a one-word name.
    await db.query("UPDATE users SET full_name = 'Madonna' WHERE id = $1", [third.user.id]);
    const tripId = await completedTrip(driver, [first, second, third]);

    await rated(first.token, { tripId, rateeId: driver.user.id, stars: 5, review: 'Great' });
    await rated(second.token, { tripId, rateeId: driver.user.id, stars: 4 });
    await rated(third.token, { tripId, rateeId: driver.user.id, stars: 4 });
    // The driver's ratings of passengers are not part of the driver's received ratings.
    await rated(driver.token, { tripId, rateeId: first.user.id, stars: 1 });

    const res = await get(`/ratings/users/${driver.user.id}`, first.token);

    expect(res.status).toBe(200);
    expect(res.body.data).toMatchObject({ averageRating: 4.33, ratingCount: 3 });
    expect(res.body.meta).toEqual({ page: 1, limit: 20, total: 3, totalPages: 1 });
    const { ratings } = res.body.data;
    expect(ratings.map((r) => r.reviewer.name)).toEqual(['Madonna', 'Sunil F.', 'Nimal S.']);
    expect(ratings[2]).toMatchObject({
      stars: 5,
      review: 'Great',
      raterRole: 'PASSENGER',
      reviewer: { id: first.user.id, name: 'Nimal S.' },
      trip: { id: tripId, originName: 'Colombo Fort', destinationName: 'Kandy' },
    });
    // Full names never leave the server.
    expect(JSON.stringify(res.body)).not.toContain('Silva');
  });

  test('a passenger average comes from the ratings drivers gave them', async () => {
    const driverA = await signedInDriver();
    const driverB = await signedInDriver({ firstName: 'Saman', lastName: 'Kumara' });
    const passenger = await signedInPassenger();
    const tripA = await completedTrip(driverA, [passenger]);
    const tripB = await completedTrip(driverB, [passenger]);

    await rated(driverA.token, { tripId: tripA, rateeId: passenger.user.id, stars: 4 });
    await rated(driverB.token, { tripId: tripB, rateeId: passenger.user.id, stars: 3 });

    const all = await get(`/ratings/users/${passenger.user.id}`, driverA.token);
    expect(all.body.data).toMatchObject({ averageRating: 3.5, ratingCount: 2 });

    const asPassenger = await get(`/ratings/users/${passenger.user.id}?role=PASSENGER`, driverA.token);
    expect(asPassenger.body.data).toMatchObject({ averageRating: 3.5, ratingCount: 2 });

    const asDriver = await get(`/ratings/users/${passenger.user.id}?role=DRIVER`, driverA.token);
    expect(asDriver.body.data).toEqual({ averageRating: null, ratingCount: 0, ratings: [] });
  });

  test('pages the ratings', async () => {
    const driver = await signedInDriver();
    const passengers = [
      await signedInPassenger(),
      await signedInPassenger({ firstName: 'Sunil', lastName: 'Fernando' }),
      await signedInPassenger({ firstName: 'Ruwan', lastName: 'Jayasuriya' }),
    ];
    const tripId = await completedTrip(driver, passengers);
    for (const passenger of passengers) await rated(passenger.token, { tripId, rateeId: driver.user.id, stars: 4 });

    const page2 = await get(`/ratings/users/${driver.user.id}?page=2&limit=2`, driver.token);
    expect(page2.body.meta).toEqual({ page: 2, limit: 2, total: 3, totalPages: 2 });
    expect(page2.body.data.ratings).toHaveLength(1);
    expect(page2.body.data.ratingCount).toBe(3);
  });

  test('a user with no ratings, an unknown user and a bad id', async () => {
    const passenger = await signedInPassenger();

    const none = await get(`/ratings/users/${passenger.user.id}`, passenger.token);
    expect(none.body.data).toEqual({ averageRating: null, ratingCount: 0, ratings: [] });

    expectError(await get(`/ratings/users/${crypto.randomUUID()}`, passenger.token), 404, 'USER_NOT_FOUND');
    expectError(await get('/ratings/users/not-a-uuid', passenger.token), 422, 'VALIDATION_ERROR');
    expectError(await get(`/ratings/users/${passenger.user.id}?role=ADMIN`, passenger.token), 422, 'VALIDATION_ERROR');
  });
});

describe('GET /ratings/mine', () => {
  test('lists the ratings the user gave, newest first', async () => {
    const driver = await signedInDriver();
    const first = await signedInPassenger();
    const second = await signedInPassenger({ firstName: 'Sunil', lastName: 'Fernando' });
    const tripId = await completedTrip(driver, [first, second]);

    await rated(driver.token, { tripId, rateeId: first.user.id, stars: 4 });
    await rated(driver.token, { tripId, rateeId: second.user.id, stars: 2, review: 'Late' });
    await rated(first.token, { tripId, rateeId: driver.user.id });

    const res = await get('/ratings/mine', driver.token);
    expect(res.status).toBe(200);
    expect(res.body.meta).toEqual({ page: 1, limit: 20, total: 2, totalPages: 1 });
    expect(res.body.data.ratings).toEqual([
      expect.objectContaining({ stars: 2, review: 'Late', raterRole: 'DRIVER', ratee: { id: second.user.id, name: 'Sunil F.' } }),
      expect.objectContaining({ stars: 4, ratee: { id: first.user.id, name: 'Nimal S.' }, trip: expect.objectContaining({ id: tripId }) }),
    ]);

    expect((await get('/ratings/mine', second.token)).body.data.ratings).toEqual([]);
    expectError(await get('/ratings/mine?limit=51', driver.token), 422, 'VALIDATION_ERROR');
  });
});

describe('signed out', () => {
  test('every rating endpoint returns 401', async () => {
    const id = crypto.randomUUID();
    expect((await post('/ratings', { tripId: id, rateeId: id, stars: 5 })).status).toBe(401);
    expect((await get('/ratings/pending')).status).toBe(401);
    expect((await get(`/ratings/users/${id}`)).status).toBe(401);
    expect((await get('/ratings/mine')).status).toBe(401);
  });
});
