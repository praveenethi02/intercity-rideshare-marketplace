const db = require('../src/db');
const seedAdmin = require('../src/db/seed-admin');
const bookingRepository = require('../src/modules/bookings/booking.repository');
const { post, get, patch, signedInUser } = require('./helpers/api');
const { startTestDb, resetTestDb, stopTestDb } = require('./helpers/test-db');

beforeAll(startTestDb);
beforeEach(resetTestDb);
afterAll(stopTestDb);

const inHours = (hours) => new Date(Date.now() + hours * 3_600_000).toISOString();

// Stops 0..3, so legs 0..2.
const STOPS = [
  { name: 'Colombo Fort', lat: 6.9344, lng: 79.8428 },
  { name: 'Kadawatha', lat: 7.001, lng: 79.953 },
  { name: 'Kegalle', lat: 7.2513, lng: 80.3464 },
  { name: 'Kandy', lat: 7.2906, lng: 80.6337 },
];

// ---------- set-up helpers (same data as trips.test.js) ----------

async function approveDriver(userId) {
  await db.query(
    `INSERT INTO driver_profiles (user_id, license_number, license_expiry, nic_number, verification_status)
     VALUES ($1, $2, '2030-01-01', $3, 'APPROVED')`,
    [userId, `B${userId.slice(0, 8)}`, `N${userId.slice(0, 11)}`],
  );
}

let plateCounter = 5000;

async function addVehicle(driverUserId) {
  plateCounter += 1;
  const { rows } = await db.query(
    `INSERT INTO vehicles (driver_user_id, vehicle_type, make, model, year, color, plate_number,
       total_seats, passenger_seats, verification_status, is_active)
     VALUES ($1, 'CAR', 'Toyota', 'Axio', 2016, 'White', $2, 5, 4, 'APPROVED', TRUE)
     RETURNING id`,
    [driverUserId, `WP CAB-${plateCounter}`],
  );
  return rows[0].id;
}

async function signedInDriver() {
  const { user, tokens } = await signedInUser({ role: 'DRIVER' });
  await approveDriver(user.id);
  const vehicleId = await addVehicle(user.id);
  return { user, token: tokens.accessToken, vehicleId };
}

async function signedInPassenger() {
  const { user, tokens } = await signedInUser({ role: 'PASSENGER' });
  return { user, token: tokens.accessToken };
}

const ADMIN = { ADMIN_NAME: 'System Admin', ADMIN_PHONE: '0770000001', ADMIN_PASSWORD: 'Adm1nPassword' };

async function signedInAdmin() {
  await seedAdmin(ADMIN);
  const res = await post('/auth/login', { phone: ADMIN.ADMIN_PHONE, password: ADMIN.ADMIN_PASSWORD });
  expect(res.status).toBe(200);
  return { user: res.body.data.user, token: res.body.data.tokens.accessToken };
}

/** A trip of `driver`. publish: false leaves it as a DRAFT. */
async function tripOf(driver, { publish = true, ...overrides } = {}) {
  const created = await post(
    '/trips',
    {
      vehicleId: driver.vehicleId,
      pricingMode: 'FIXED',
      departureAt: inHours(26),
      seatsOffered: 3,
      basePriceCents: 250000,
      stops: STOPS,
      ...overrides,
    },
    driver.token,
  );
  expect(created.status).toBe(201);
  if (!publish) return created.body.data.trip;
  const published = await post(`/trips/${created.body.data.trip.id}/publish`, {}, driver.token);
  expect(published.status).toBe(200);
  return published.body.data.trip;
}

const book = (token, body) => post('/bookings', { fromStop: 0, toStop: 3, seats: 1, ...body }, token);

async function booked(token, body) {
  const res = await book(token, body);
  expect(res.status).toBe(201);
  return res.body.data.booking;
}

const availability = async (token, tripId, fromStop, toStop) =>
  (await get(`/trips/${tripId}/availability?fromStop=${fromStop}&toStop=${toStop}`, token)).body.data.availability;

const expectError = (res, status, code) => {
  expect(res.status).toBe(status);
  expect(res.body.meta.code).toBe(code);
};

// ---------- tests ----------

describe('POST /bookings', () => {
  test('books a segment with the price from the trip and reduces only that segment', async () => {
    const driver = await signedInDriver();
    const trip = await tripOf(driver);
    const passenger = await signedInPassenger();
    const { segmentPriceCents } = await availability(passenger.token, trip.id, 1, 2);

    const booking = await booked(passenger.token, { tripId: trip.id, fromStop: 1, toStop: 2, seats: 2 });

    expect(booking).toMatchObject({
      status: 'CONFIRMED',
      tripId: trip.id,
      passengerId: passenger.user.id,
      fromStop: 1,
      toStop: 2,
      seats: 2,
      pricePerSeatCents: segmentPriceCents,
      totalCents: 2 * segmentPriceCents,
      pickup: { stopOrder: 1, name: 'Kadawatha' },
      drop: { stopOrder: 2, name: 'Kegalle' },
      trip: { id: trip.id, status: 'SCHEDULED', originName: 'Colombo Fort', destinationName: 'Kandy' },
    });
    expect(booking.reference).toMatch(/^BK-[A-HJ-NP-Z2-9]{6}$/);
    expect(segmentPriceCents).toBeGreaterThan(0);
    expect(segmentPriceCents).toBeLessThan(250000);

    // Kadawatha -> Kegalle (leg 1) has 1 seat left; the legs before and after are untouched.
    expect((await availability(passenger.token, trip.id, 1, 2)).seatsAvailable).toBe(1);
    expect((await availability(passenger.token, trip.id, 0, 3)).seatsAvailable).toBe(1);
    expect((await availability(passenger.token, trip.id, 0, 1)).seatsAvailable).toBe(3);
    expect((await availability(passenger.token, trip.id, 2, 3)).seatsAvailable).toBe(3);
  });

  test('never takes a price from the client', async () => {
    const driver = await signedInDriver();
    const trip = await tripOf(driver);
    const passenger = await signedInPassenger();

    const res = await book(passenger.token, { tripId: trip.id, pricePerSeatCents: 100, totalCents: 100 });

    expectError(res, 422, 'VALIDATION_ERROR');
    expect((await availability(passenger.token, trip.id, 0, 3)).seatsAvailable).toBe(3);
  });

  test('keeps the price saved at booking time', async () => {
    const driver = await signedInDriver();
    const trip = await tripOf(driver);
    const passenger = await signedInPassenger();
    const booking = await booked(passenger.token, { tripId: trip.id, seats: 2 });
    expect(booking).toMatchObject({ pricePerSeatCents: 250000, totalCents: 500000 });

    await db.query('UPDATE trips SET base_price_cents = 999000 WHERE id = $1', [trip.id]);

    const res = await get(`/bookings/${booking.id}`, passenger.token);
    expect(res.body.data.booking).toMatchObject({ pricePerSeatCents: 250000, totalCents: 500000 });
  });

  test('stops with PRICE_CHANGED if the driver changes the price while the booking is made', async () => {
    const driver = await signedInDriver();
    const trip = await tripOf(driver);
    const passenger = await signedInPassenger();
    // The first read (before the transaction) sees the old price; then the driver edits it.
    const findTrip = bookingRepository.findTrip;
    const spy = jest.spyOn(bookingRepository, 'findTrip').mockImplementationOnce(async (...args) => {
      const row = await findTrip(...args);
      const edited = await patch(`/trips/${trip.id}`, driver.token, { basePriceCents: 300000 });
      expect(edited.status).toBe(200);
      return row;
    });

    try {
      expectError(await book(passenger.token, { tripId: trip.id }), 409, 'PRICE_CHANGED');
    } finally {
      spy.mockRestore();
    }

    // The seats were rolled back, and a new try books at the new price.
    expect((await availability(passenger.token, trip.id, 0, 3)).seatsAvailable).toBe(3);
    expect(await booked(passenger.token, { tripId: trip.id })).toMatchObject({ pricePerSeatCents: 300000 });
  });

  test('cannot oversell the last seat', async () => {
    const driver = await signedInDriver();
    const trip = await tripOf(driver); // 3 seats
    const [a, b, c, d] = await Promise.all([1, 2, 3, 4].map(() => signedInPassenger()));
    await booked(a.token, { tripId: trip.id, seats: 2 });

    const tooMany = await book(b.token, { tripId: trip.id, seats: 2 });
    expectError(tooMany, 409, 'NOT_ENOUGH_SEATS');
    expect(tooMany.body.meta.details).toEqual({ seatsAvailable: 1 });

    // Two passengers try for the last seat at the same time: exactly one gets it.
    const results = await Promise.all([c, d].map((p) => book(p.token, { tripId: trip.id })));
    expect(results.map((r) => r.status).sort()).toEqual([201, 409]);
    expect(results.find((r) => r.status === 409).body.meta.code).toBe('NOT_ENOUGH_SEATS');
    expect((await availability(a.token, trip.id, 0, 3)).seatsAvailable).toBe(0);
    const { rows } = await db.query("SELECT count(*)::int AS n FROM bookings WHERE status = 'CONFIRMED'");
    expect(rows[0].n).toBe(2);
  });

  test('refuses an AUCTION trip', async () => {
    const driver = await signedInDriver();
    const trip = await tripOf(driver, { pricingMode: 'AUCTION' });
    const passenger = await signedInPassenger();

    expectError(await book(passenger.token, { tripId: trip.id }), 409, 'AUCTION_TRIP');
  });

  test("refuses the driver's own trip", async () => {
    const driver = await signedInDriver();
    const trip = await tripOf(driver);

    expectError(await book(driver.token, { tripId: trip.id }), 403, 'OWN_TRIP');
  });

  test('a driver can book a seat on another driver’s trip', async () => {
    const driver = await signedInDriver();
    const otherDriver = await signedInDriver();
    const trip = await tripOf(driver);

    expect((await book(otherDriver.token, { tripId: trip.id })).status).toBe(201);
  });

  test('refuses a draft, a missing trip and trips that are not SCHEDULED', async () => {
    const driver = await signedInDriver();
    const passenger = await signedInPassenger();

    const draft = await tripOf(driver, { publish: false });
    expectError(await book(passenger.token, { tripId: draft.id }), 404, 'TRIP_NOT_FOUND');
    expectError(await book(passenger.token, { tripId: crypto.randomUUID() }), 404, 'TRIP_NOT_FOUND');

    const cancelled = await tripOf(driver);
    expect((await post(`/trips/${cancelled.id}/cancel`, { reason: 'Car broke down' }, driver.token)).status).toBe(200);
    expectError(await book(passenger.token, { tripId: cancelled.id }), 409, 'TRIP_NOT_BOOKABLE');

    const started = await tripOf(driver, { departureAt: inHours(30) });
    await db.query("UPDATE trips SET departure_at = now() + interval '10 minutes' WHERE id = $1", [started.id]);
    expect((await post(`/trips/${started.id}/start`, {}, driver.token)).status).toBe(200);
    expectError(await book(passenger.token, { tripId: started.id }), 409, 'TRIP_NOT_BOOKABLE');
  });

  test('refuses a SCHEDULED trip whose departure time has passed', async () => {
    const driver = await signedInDriver();
    const trip = await tripOf(driver);
    await db.query("UPDATE trips SET departure_at = now() - interval '5 minutes' WHERE id = $1", [trip.id]);
    const passenger = await signedInPassenger();

    expectError(await book(passenger.token, { tripId: trip.id }), 409, 'TRIP_DEPARTED');
  });

  test.each([
    ['drop before pickup', { fromStop: 2, toStop: 1 }],
    ['same stop', { fromStop: 2, toStop: 2 }],
    ['stop not on the trip', { fromStop: 1, toStop: 9 }],
  ])('refuses invalid stops: %s', async (_, stops) => {
    const driver = await signedInDriver();
    const trip = await tripOf(driver);
    const passenger = await signedInPassenger();

    expectError(await book(passenger.token, { tripId: trip.id, ...stops }), 422, 'INVALID_SEGMENT');
    expect((await availability(passenger.token, trip.id, 0, 3)).seatsAvailable).toBe(3);
  });

  test.each([
    ['no seats', { seats: 0 }],
    ['too many seats', { seats: 15 }],
    ['negative stop', { fromStop: -1 }],
    ['bad trip id', { tripId: 'not-a-uuid' }],
  ])('validates the body: %s', async (_, body) => {
    const passenger = await signedInPassenger();
    expectError(await book(passenger.token, { tripId: crypto.randomUUID(), ...body }), 422, 'VALIDATION_ERROR');
  });

  test('one confirmed booking per passenger per trip, a new one is allowed after cancelling', async () => {
    const driver = await signedInDriver();
    const trip = await tripOf(driver);
    const passenger = await signedInPassenger();
    const first = await booked(passenger.token, { tripId: trip.id, fromStop: 0, toStop: 1 });

    expectError(await book(passenger.token, { tripId: trip.id, fromStop: 2, toStop: 3 }), 409, 'ALREADY_BOOKED');

    expect((await post(`/bookings/${first.id}/cancel`, {}, passenger.token)).status).toBe(200);
    const second = await booked(passenger.token, { tripId: trip.id, fromStop: 2, toStop: 3 });
    expect(second.reference).not.toBe(first.reference);
  });

  test('two bookings at once by the same passenger: one wins, the other gets ALREADY_BOOKED', async () => {
    const driver = await signedInDriver();
    const trip = await tripOf(driver);
    const passenger = await signedInPassenger();

    const results = await Promise.all([0, 1].map(() => book(passenger.token, { tripId: trip.id })));

    expect(results.map((r) => r.status).sort()).toEqual([201, 409]);
    expect(results.find((r) => r.status === 409).body.meta.code).toBe('ALREADY_BOOKED');
    // The loser's seats were rolled back with its transaction.
    expect((await availability(passenger.token, trip.id, 0, 3)).seatsAvailable).toBe(2);
  });

  test('requires being signed in', async () => {
    expect((await post('/bookings', { tripId: crypto.randomUUID(), fromStop: 0, toStop: 1, seats: 1 })).status).toBe(401);
    expect((await get('/bookings/mine')).status).toBe(401);
  });
});

describe('POST /bookings/:id/cancel', () => {
  test('gives the seats back and cannot be done twice', async () => {
    const driver = await signedInDriver();
    const trip = await tripOf(driver);
    const passenger = await signedInPassenger();
    const booking = await booked(passenger.token, { tripId: trip.id, fromStop: 0, toStop: 2, seats: 3 });
    expect((await availability(passenger.token, trip.id, 1, 2)).seatsAvailable).toBe(0);

    const res = await post(`/bookings/${booking.id}/cancel`, { reason: 'Plans changed' }, passenger.token);

    expect(res.status).toBe(200);
    expect(res.body.data.booking).toMatchObject({ status: 'CANCELLED', cancelReason: 'Plans changed' });
    expect(res.body.data.booking.cancelledAt).not.toBeNull();
    expect((await availability(passenger.token, trip.id, 0, 3)).seatsAvailable).toBe(3);
    expect((await get(`/trips/${trip.id}`, driver.token)).body.data.trip.seatsAvailable).toBe(3);

    expectError(await post(`/bookings/${booking.id}/cancel`, {}, passenger.token), 409, 'ALREADY_CANCELLED');
    expect((await availability(passenger.token, trip.id, 0, 3)).seatsAvailable).toBe(3);
  });

  test('only while the trip is SCHEDULED, and keeps the seats otherwise', async () => {
    const driver = await signedInDriver();
    const trip = await tripOf(driver);
    const passenger = await signedInPassenger();
    const booking = await booked(passenger.token, { tripId: trip.id, seats: 2 });
    await db.query("UPDATE trips SET departure_at = now() + interval '10 minutes' WHERE id = $1", [trip.id]);
    expect((await post(`/trips/${trip.id}/start`, {}, driver.token)).status).toBe(200);

    expectError(await post(`/bookings/${booking.id}/cancel`, {}, passenger.token), 409, 'TRIP_NOT_CANCELLABLE');

    const after = await get(`/bookings/${booking.id}`, passenger.token);
    expect(after.body.data.booking.status).toBe('CONFIRMED');
    const { rows } = await db.query('SELECT max(seats_reserved)::int AS reserved FROM trip_legs WHERE trip_id = $1', [
      trip.id,
    ]);
    expect(rows[0].reserved).toBe(2);
  });

  test('validates the reason', async () => {
    const passenger = await signedInPassenger();
    expectError(
      await post(`/bookings/${crypto.randomUUID()}/cancel`, { reason: 'x' }, passenger.token),
      422,
      'VALIDATION_ERROR',
    );
  });
});

describe('who can see and cancel a booking', () => {
  test('the passenger, the driver and an admin can see it; others get 404', async () => {
    const driver = await signedInDriver();
    const trip = await tripOf(driver);
    const passenger = await signedInPassenger();
    const stranger = await signedInPassenger();
    const otherDriver = await signedInDriver();
    const admin = await signedInAdmin();
    const booking = await booked(passenger.token, { tripId: trip.id });

    for (const viewer of [passenger, driver, admin]) {
      const res = await get(`/bookings/${booking.id}`, viewer.token);
      expect(res.status).toBe(200);
      expect(res.body.data.booking.reference).toBe(booking.reference);
    }
    for (const viewer of [stranger, otherDriver]) {
      expectError(await get(`/bookings/${booking.id}`, viewer.token), 404, 'BOOKING_NOT_FOUND');
    }
    expectError(await get(`/bookings/${crypto.randomUUID()}`, passenger.token), 404, 'BOOKING_NOT_FOUND');
  });

  test('only the passenger can cancel', async () => {
    const driver = await signedInDriver();
    const trip = await tripOf(driver);
    const passenger = await signedInPassenger();
    const stranger = await signedInPassenger();
    const admin = await signedInAdmin();
    const booking = await booked(passenger.token, { tripId: trip.id });

    for (const other of [stranger, driver, admin]) {
      expectError(await post(`/bookings/${booking.id}/cancel`, {}, other.token), 404, 'BOOKING_NOT_FOUND');
    }
    expect((await get(`/bookings/${booking.id}`, passenger.token)).body.data.booking.status).toBe('CONFIRMED');
  });
});

describe('GET /bookings/mine', () => {
  test('lists only my bookings, newest first, with upcoming and past filters and paging', async () => {
    const driver = await signedInDriver();
    const tripA = await tripOf(driver);
    const tripB = await tripOf(driver, { departureAt: inHours(50) });
    const tripC = await tripOf(driver, { departureAt: inHours(70) });
    const me = await signedInPassenger();
    const other = await signedInPassenger();

    const cancelled = await booked(me.token, { tripId: tripA.id });
    await post(`/bookings/${cancelled.id}/cancel`, {}, me.token);
    const upcoming = await booked(me.token, { tripId: tripB.id, fromStop: 1, toStop: 3 });
    const completed = await booked(me.token, { tripId: tripC.id });
    await db.query("UPDATE trips SET status = 'COMPLETED', completed_at = now() WHERE id = $1", [tripC.id]);
    await booked(other.token, { tripId: tripB.id });
    // Make the order certain: the newest booking first.
    await db.query("UPDATE bookings SET created_at = now() - interval '3 minutes' WHERE id = $1", [cancelled.id]);
    await db.query("UPDATE bookings SET created_at = now() - interval '2 minutes' WHERE id = $1", [upcoming.id]);
    await db.query("UPDATE bookings SET created_at = now() - interval '1 minute' WHERE id = $1", [completed.id]);

    const all = await get('/bookings/mine', me.token);
    expect(all.status).toBe(200);
    expect(all.body.data.bookings.map((b) => b.id)).toEqual([completed.id, upcoming.id, cancelled.id]);
    expect(all.body.meta).toMatchObject({ page: 1, limit: 20, total: 3, totalPages: 1 });
    expect(all.body.data.bookings[1]).toMatchObject({
      pickup: { name: 'Kadawatha' },
      drop: { name: 'Kandy' },
      trip: { status: 'SCHEDULED', departureAt: expect.any(String) },
    });

    const next = await get('/bookings/mine?when=upcoming', me.token);
    expect(next.body.data.bookings.map((b) => b.id)).toEqual([upcoming.id]);

    const past = await get('/bookings/mine?when=past', me.token);
    expect(past.body.data.bookings.map((b) => b.id)).toEqual([completed.id, cancelled.id]);

    const page2 = await get('/bookings/mine?limit=2&page=2', me.token);
    expect(page2.body.data.bookings.map((b) => b.id)).toEqual([cancelled.id]);
    expect(page2.body.meta).toMatchObject({ page: 2, limit: 2, total: 3, totalPages: 2 });

    expectError(await get('/bookings/mine?when=soon', me.token), 422, 'VALIDATION_ERROR');
  });
});
