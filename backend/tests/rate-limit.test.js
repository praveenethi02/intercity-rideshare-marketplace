process.env.RATE_LIMIT_ENABLED = 'true';
process.env.AUTH_RATE_LIMIT_MAX = '2';

const { post } = require('./helpers/api');
const { startTestDb, stopTestDb } = require('./helpers/test-db');

beforeAll(startTestDb);
afterAll(stopTestDb);

test('auth endpoints return 429 after too many attempts', async () => {
  const attempt = () => post('/auth/login', { phone: '0771234567', password: 'Wr0ngPass' });

  expect((await attempt()).status).toBe(401);
  expect((await attempt()).status).toBe(401);

  const blocked = await attempt();
  expect(blocked.status).toBe(429);
  expect(blocked.body.meta.code).toBe('TOO_MANY_REQUESTS');
});
