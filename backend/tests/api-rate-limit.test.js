// Trips, saved routes and bookings have their own per-IP limit, separate from sign in.
process.env.RATE_LIMIT_ENABLED = 'true';
process.env.AUTH_RATE_LIMIT_MAX = '3';
process.env.API_RATE_LIMIT_MAX = '3';

const { get, post, signedInUser } = require('./helpers/api');
const { startTestDb, stopTestDb } = require('./helpers/test-db');

beforeAll(startTestDb);
afterAll(stopTestDb);

const UNKNOWN_TRIP = '00000000-0000-4000-8000-000000000000';

test('trips and bookings share one limit that is separate from the auth limit', async () => {
  // Registering and verifying use 2 of the 3 auth requests.
  const { tokens } = await signedInUser();
  const token = tokens.accessToken;

  // Three app requests, across bookings and trips, are allowed.
  expect((await get('/bookings/mine', token)).status).toBe(200);
  expect((await get(`/trips/${UNKNOWN_TRIP}`, token)).status).toBe(404);
  expect((await get('/bookings/mine', token)).status).toBe(200);

  // The fourth is blocked.
  const blocked = await get('/bookings/mine', token);
  expect(blocked.status).toBe(429);
  expect(blocked.body.meta.code).toBe('TOO_MANY_REQUESTS');

  // Sign in still has its own count: the third auth request is allowed (wrong password, not 429).
  const login = await post('/auth/login', { phone: '0771234567', password: 'Wr0ngPass' });
  expect(login.status).toBe(401);
});