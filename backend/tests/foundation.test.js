const request = require('supertest');
const createApp = require('../src/app');
const db = require('../src/db');
const userRepository = require('../src/modules/users/user.repository');
const { ROLES, SELECTABLE_ROLES, USER_STATUS } = require('../src/modules/users/user.constants');
const { normalizePhone } = require('../src/utils/phone');
const { startTestDb, resetTestDb, stopTestDb } = require('./helpers/test-db');

const app = createApp();

beforeAll(startTestDb);
beforeEach(resetTestDb);
afterAll(stopTestDb);

describe('API foundation', () => {
  test('GET /health reports a healthy service in the standard envelope', async () => {
    const res = await request(app).get('/health');

    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      success: true,
      message: 'Service is healthy',
      data: { status: 'ok' },
      meta: null,
    });
  });

  test('unknown routes return a 404 envelope', async () => {
    const res = await request(app).get('/nope');

    expect(res.status).toBe(404);
    expect(res.body.success).toBe(false);
    expect(res.body.meta.code).toBe('NOT_FOUND');
  });

  test('malformed JSON returns 400, not 500', async () => {
    const res = await request(app)
      .post('/health')
      .set('Content-Type', 'application/json')
      .send('{ not json');

    expect(res.status).toBe(400);
    expect(res.body.meta.code).toBe('INVALID_JSON');
  });
});

describe('phone normalisation', () => {
  test.each(['0771234567', '94771234567', '+94771234567', '077 123-4567'])('accepts %s', (input) => {
    expect(normalizePhone(input)).toBe('+94771234567');
  });

  test.each(['0112345678', '077123456', '+14155552671', 'phone', ''])('rejects "%s"', (input) => {
    expect(normalizePhone(input)).toBeNull();
  });
});

describe('user model', () => {
  const base = {
    fullName: 'Test User',
    phone: '+94771234567',
    passwordHash: 'hash',
    role: ROLES.PASSENGER,
    status: USER_STATUS.ACTIVE,
  };

  test('ADMIN is a role but cannot be self-selected', () => {
    expect(Object.values(ROLES)).toContain('ADMIN');
    expect(SELECTABLE_ROLES).not.toContain('ADMIN');
  });

  test('public user never exposes the password hash', async () => {
    const user = await userRepository.create(base);

    expect(userRepository.toPublicUser(user)).not.toHaveProperty('passwordHash');
    expect(JSON.stringify(userRepository.toPublicUser(user))).not.toContain('hash"');
    expect(await userRepository.findByPhone(base.phone)).toMatchObject({ id: user.id });
  });

  test('phone numbers and emails (case-insensitive) are unique', async () => {
    await userRepository.create({ ...base, email: 'Same@Example.com' });

    await expect(userRepository.create(base)).rejects.toMatchObject({ code: '23505' });
    await expect(
      userRepository.create({ ...base, phone: '+94771234568', email: 'same@example.com' }),
    ).rejects.toMatchObject({ code: '23505' });
  });

  test('the database rejects an unknown role', async () => {
    await expect(
      db.query(
        `INSERT INTO users (full_name, phone, password_hash, role)
         VALUES ('x', '+94770000000', 'h', 'SUPERUSER')`,
      ),
    ).rejects.toThrow();
  });
});
