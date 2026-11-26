const db = require('../src/db');
const seedAdmin = require('../src/db/seed-admin');
const { post, get, signedInUser } = require('./helpers/api');
const { startTestDb, resetTestDb, stopTestDb } = require('./helpers/test-db');

beforeAll(startTestDb);
beforeEach(resetTestDb);
afterAll(stopTestDb);

const inHours = (hours) => new Date(Date.now() + hours * 3_600_000).toISOString();

const STOPS = [
  { name: 'Colombo Fort', lat: 6.9344, lng: 79.8428 },
  { name: 'Kadawatha', lat: 7.001, lng: 79.953 },
  { name: 'Kandy', lat: 7.2906, lng: 80.6337 },
];

const ADMIN = { ADMIN_NAME: 'System Admin', ADMIN_PHONE: '0770000001', ADMIN_PASSWORD: 'Adm1nPassword' };

async function signedInAdmin() {
  await seedAdmin(ADMIN);
  const res = await post('/auth/login', { phone: ADMIN.ADMIN_PHONE, password: ADMIN.ADMIN_PASSWORD });
  expect(res.status).toBe(200);
  return res.body.data.tokens.accessToken;
}

let plate = 7000;

async function signedInDriver() {
  const { user, tokens } = await signedInUser({ role: 'DRIVER', firstName: 'Kamal', lastName: 'Perera' });
  await db.query(
    `INSERT INTO driver_profiles (user_id, license_number, license_expiry, nic_number, verification_status)
     VALUES ($1, $2, '2030-01-01', $3, 'APPROVED')`,
    [user.id, `B${user.id.slice(0, 8)}`, `N${user.id.slice(0, 11)}`],
  );
  plate += 1;
  const { rows } = await db.query(
    `INSERT INTO vehicles (driver_user_id, vehicle_type, make, model, year, color, plate_number,
       total_seats, passenger_seats, verification_status, is_active)
     VALUES ($1, 'CAR', 'Toyota', 'Axio', 2016, 'White', $2, 5, 4, 'APPROVED', TRUE)
     RETURNING id`,
    [user.id, `WP CAB-${plate}`],
  );
  return { user, token: tokens.accessToken, vehicleId: rows[0].id };
}

async function publishedTrip(driver) {
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
  const published = await post(`/trips/${created.body.data.trip.id}/publish`, {}, driver.token);
  expect(published.status).toBe(200);
  return published.body.data.trip;
}

async function bookingBy(firstName, tripId) {
  const { user, tokens } = await signedInUser({ firstName, lastName: 'Silva' });
  const res = await post('/bookings', { tripId, fromStop: 0, toStop: 2, seats: 1 }, tokens.accessToken);
  expect(res.status).toBe(201);
  return { user, token: tokens.accessToken, booking: res.body.data.booking };
}

/** One driver's trip with two bookings: Nimal's is confirmed, Sunil's is cancelled. */
async function twoBookings() {
  const driver = await signedInDriver();
  const trip = await publishedTrip(driver);
  const nimal = await bookingBy('Nimal', trip.id);
  const sunil = await bookingBy('Sunil', trip.id);
  const cancelled = await post(`/bookings/${sunil.booking.id}/cancel`, { reason: 'Plans changed' }, sunil.token);
  expect(cancelled.status).toBe(200);
  return { driver, trip, nimal, sunil };
}

const list = (token, query = '') => get(`/admin/bookings${query}`, token);

describe('GET /admin/bookings', () => {
  test('lists every booking, newest first, with the passenger and the driver', async () => {
    const { driver, nimal, sunil } = await twoBookings();
    const admin = await signedInAdmin();

    const res = await list(admin);

    expect(res.status).toBe(200);
    expect(res.body.meta).toMatchObject({ page: 1, limit: 20, total: 2, totalPages: 1 });
    const [first, second] = res.body.data.bookings;
    expect(first).toMatchObject({ id: sunil.booking.id, status: 'CANCELLED', cancelReason: 'Plans changed' });
    expect(second).toMatchObject({ id: nimal.booking.id, status: 'CONFIRMED', totalCents: 250000 });
    expect(second.passenger).toEqual({ id: nimal.user.id, fullName: 'Nimal Silva', phone: nimal.user.phone });
    expect(second.driver).toEqual({ id: driver.user.id, fullName: 'Kamal Perera', phone: driver.user.phone });
    expect(second.trip).toMatchObject({ originName: 'Colombo Fort', destinationName: 'Kandy', status: 'SCHEDULED' });
  });

  test('filters by booking status and trip status', async () => {
    const { nimal, sunil } = await twoBookings();
    const admin = await signedInAdmin();

    const confirmed = await list(admin, '?status=CONFIRMED');
    expect(confirmed.body.data.bookings.map((b) => b.id)).toEqual([nimal.booking.id]);

    const cancelled = await list(admin, '?status=CANCELLED');
    expect(cancelled.body.data.bookings.map((b) => b.id)).toEqual([sunil.booking.id]);

    expect((await list(admin, '?tripStatus=SCHEDULED')).body.meta.total).toBe(2);
    expect((await list(admin, '?tripStatus=COMPLETED')).body.meta.total).toBe(0);
  });

  test('searches the reference, the passenger and the route', async () => {
    const { nimal } = await twoBookings();
    const admin = await signedInAdmin();
    const ids = async (search) =>
      (await list(admin, `?search=${encodeURIComponent(search)}`)).body.data.bookings.map((b) => b.id);

    expect(await ids(nimal.booking.reference.toLowerCase())).toEqual([nimal.booking.id]);
    expect(await ids('nimal')).toEqual([nimal.booking.id]);
    expect(await ids(nimal.user.phone.slice(-6))).toEqual([nimal.booking.id]);
    expect(await ids('kandy')).toHaveLength(2);
    // % and _ are taken literally, not as LIKE wildcards.
    expect(await ids('%')).toEqual([]);
    expect(await ids('_')).toEqual([]);
  });

  test('pages the results', async () => {
    await twoBookings();
    const admin = await signedInAdmin();

    const page2 = await list(admin, '?limit=1&page=2');

    expect(page2.body.data.bookings).toHaveLength(1);
    expect(page2.body.meta).toMatchObject({ page: 2, limit: 1, total: 2, totalPages: 2 });
  });

  test('rejects unknown filters and bad values', async () => {
    const admin = await signedInAdmin();
    for (const query of ['?status=PENDING', '?tripStatus=LATE', '?limit=101', '?page=0', '?when=past']) {
      const res = await list(admin, query);
      expect(res.status).toBe(422);
      expect(res.body.meta.code).toBe('VALIDATION_ERROR');
    }
  });

  test('only admins can use it', async () => {
    const { driver, nimal } = await twoBookings();

    expect((await list()).status).toBe(401);
    expect((await list(nimal.token)).status).toBe(403);
    expect((await list(driver.token)).status).toBe(403);
    expect((await get(`/admin/bookings/${nimal.booking.id}`, nimal.token)).status).toBe(403);
  });
});

describe('GET /admin/bookings/:id', () => {
  test('shows the journey, the vehicle with its plate, and both people', async () => {
    const { driver, sunil } = await twoBookings();
    const admin = await signedInAdmin();

    const res = await get(`/admin/bookings/${sunil.booking.id}`, admin);

    expect(res.status).toBe(200);
    const { booking } = res.body.data;
    expect(booking).toMatchObject({ reference: sunil.booking.reference, status: 'CANCELLED' });
    expect(booking.passenger.fullName).toBe('Sunil Silva');
    expect(booking.driver.id).toBe(driver.user.id);
    // Admins see the plate even on a cancelled booking.
    expect(booking.trip.vehicle).toMatchObject({ make: 'Toyota', model: 'Axio', plateNumber: `WP CAB-${plate}` });
    expect(booking.trip.stops.map((s) => s.name)).toEqual(['Colombo Fort', 'Kadawatha', 'Kandy']);
  });

  test('404 for a booking that does not exist, 422 for a bad id', async () => {
    const admin = await signedInAdmin();

    const missing = await get('/admin/bookings/6f1c2a7e-0d3b-4c41-9a51-2f7d8e9b1c11', admin);
    expect(missing.status).toBe(404);
    expect(missing.body.meta.code).toBe('BOOKING_NOT_FOUND');

    expect((await get('/admin/bookings/not-a-uuid', admin)).status).toBe(422);
  });
});